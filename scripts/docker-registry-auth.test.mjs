import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, lstat, mkdir, mkdtemp, readFile, realpath, rm, stat, symlink, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { cleanupDockerAuthConfig, createDockerAuthConfig } from "./docker-registry-auth.mjs";

const tempRoots = new Set();

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "docker-registry-auth-test-"));
  tempRoots.add(root);
  const runnerTemp = join(root, "runner-temp");
  await mkdir(runnerTemp, { mode: 0o700 });
  const githubEnv = join(root, "github-env");
  await writeFile(githubEnv, "", { mode: 0o600 });
  const home = join(root, "home");
  await mkdir(home, { mode: 0o700 });
  const originalConfig = join(home, ".docker");
  await mkdir(originalConfig, { recursive: true, mode: 0o700 });
  const pluginDir = join(originalConfig, "cli-plugins");
  await mkdir(pluginDir, { mode: 0o700 });
  const plugin = join(pluginDir, "docker-buildx");
  await writeFile(plugin, "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  await chmod(plugin, 0o700);
  const personalConfig = join(originalConfig, "config.json");
  const personalContent = '{"credsStore":"desktop","auths":{"private.example":{"auth":"must-stay-private"}}}\n';
  await writeFile(personalConfig, personalContent, { mode: 0o600 });
  const env = {
    RUNNER_TEMP: runnerTemp,
    GITHUB_ENV: githubEnv,
    HOME: home,
    DOCKER_CONFIG: originalConfig,
    DOCKER_AUTH_ENTRIES_JSON: JSON.stringify([
      { registry: "ghcr.io", usernameEnv: "GHCR_USERNAME", passwordEnv: "GHCR_TOKEN" },
      { registry: "cr.yandex", usernameEnv: "YC_USERNAME", passwordEnv: "YC_PASSWORD" },
      { registry: "docker.io", usernameEnv: "DOCKERHUB_USERNAME", passwordEnv: "DOCKERHUB_TOKEN" },
    ]),
    GHCR_USERNAME: "workflow-user",
    GHCR_TOKEN: "ghcr-secret-fixture",
    YC_USERNAME: "json_key",
    YC_PASSWORD: "yandex-secret-fixture\nwith-newline",
    DOCKERHUB_USERNAME: "dockerhub-user",
    DOCKERHUB_TOKEN: "dockerhub-secret-fixture",
  };
  return { root, runnerTemp, githubEnv, home, originalConfig, plugin, personalConfig, personalContent, env };
}

test.after(async () => {
  await Promise.all([...tempRoots].map((root) => rm(root, { recursive: true, force: true })));
  tempRoots.clear();
});

test("writes GHCR, Yandex, and Docker Hub auth to a private owned Docker config", async () => {
  const context = await fixture();
  const result = await createDockerAuthConfig({ env: context.env, platform: "linux" });
  const directory = result.dockerConfig;
  const directoryStat = await stat(directory);
  const configPath = join(directory, "config.json");
  const configStat = await stat(configPath);
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const githubEnv = await readFile(context.githubEnv, "utf8");

  assert.equal(directoryStat.uid, process.getuid?.());
  assert.equal(directoryStat.mode & 0o777, 0o700);
  assert.equal(configStat.uid, process.getuid?.());
  assert.equal(configStat.mode & 0o777, 0o600);
  assert.deepEqual(Object.keys(config.auths).sort(), ["cr.yandex", "ghcr.io", "https://index.docker.io/v1/"].sort());
  assert.equal(Buffer.from(config.auths["ghcr.io"].auth, "base64").toString(), "workflow-user:ghcr-secret-fixture");
  assert.equal(Buffer.from(config.auths["cr.yandex"].auth, "base64").toString(), "json_key:yandex-secret-fixture\nwith-newline");
  assert.equal(Buffer.from(config.auths["https://index.docker.io/v1/"].auth, "base64").toString(), "dockerhub-user:dockerhub-secret-fixture");
  assert.match(githubEnv, new RegExp(`^DOCKER_CONFIG=${directory.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")}$`, "mu"));
  assert.match(githubEnv, new RegExp(`^DOCKER_REGISTRY_AUTH_CONFIG_DIR=${directory.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")}$`, "mu"));
  assert.doesNotMatch(githubEnv, /ghcr-secret-fixture|yandex-secret-fixture|dockerhub-secret-fixture/u);
  assert.equal(await realpath(join(directory, "cli-plugins", "docker-buildx")), await realpath(context.plugin));
  assert.equal(await readFile(context.personalConfig, "utf8"), context.personalContent);
  assert.equal(result.dockerHost, undefined);
});

test("CLI setup never prints registry credentials and always exposes only the private config path", async () => {
  const context = await fixture();
  const script = fileURLToPath(new URL("./docker-registry-auth.mjs", import.meta.url));
  const socket = join(context.home, ".docker", "run", "docker.sock");
  await mkdir(join(context.home, ".docker", "run"), { recursive: true, mode: 0o700 });
  const shortSocket = join(tmpdir(), `dra-cli-${process.pid}.sock`);
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(shortSocket, resolve);
  });
  try {
    await symlink(shortSocket, socket);
    const result = spawnSync(process.execPath, [script, "create"], { encoding: "utf8", env: context.env });
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /ghcr-secret-fixture|yandex-secret-fixture|dockerhub-secret-fixture/u);
    const environment = await readFile(context.githubEnv, "utf8");
    const configPath = environment.match(/^DOCKER_CONFIG=(.+)$/mu)?.[1];
    const ownedPath = environment.match(/^DOCKER_REGISTRY_AUTH_CONFIG_DIR=(.+)$/mu)?.[1];
    assert.ok(configPath);
    assert.equal(ownedPath, configPath);
    await cleanupDockerAuthConfig({ env: { ...context.env, DOCKER_CONFIG: configPath, DOCKER_REGISTRY_AUTH_CONFIG_DIR: ownedPath } });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("Docker CLI finds a trusted Buildx plugin through the private config", async (t) => {
  if (spawnSync("docker", ["--version"], { encoding: "utf8" }).error?.code === "ENOENT") {
    t.skip("Docker CLI is not installed on this host");
    return;
  }
  const context = await fixture();
  context.env.HOME = process.env.HOME || context.home;
  delete context.env.DOCKER_CONFIG;
  const result = await createDockerAuthConfig({ env: context.env, platform: "linux" });
  const configPlugin = join(result.dockerConfig, "cli-plugins", "docker-buildx");
  try {
    try {
      await lstat(configPlugin);
    } catch (error) {
      if (error?.code === "ENOENT") {
        t.skip("No trusted system Buildx plugin is installed");
        return;
      }
      throw error;
    }
    const version = spawnSync("docker", ["--config", result.dockerConfig, "buildx", "version"], { encoding: "utf8" });
    assert.equal(version.status, 0, version.stderr);
    assert.match(version.stdout, /buildx v?\d/iu);
  } finally {
    await cleanupDockerAuthConfig({ env: { ...context.env, DOCKER_CONFIG: result.dockerConfig, DOCKER_REGISTRY_AUTH_CONFIG_DIR: result.dockerConfig } });
  }
});

test("keeps an explicit Docker host and derives the real Docker Desktop socket when absent", async () => {
  const explicit = await fixture();
  explicit.env.DOCKER_HOST = "tcp://127.0.0.1:2376";
  const explicitResult = await createDockerAuthConfig({ env: explicit.env, platform: "darwin" });
  assert.equal(explicitResult.dockerHost, undefined);
  assert.doesNotMatch(await readFile(explicit.githubEnv, "utf8"), /^DOCKER_HOST=/mu);
  await cleanupDockerAuthConfig({ env: { ...explicit.env, DOCKER_CONFIG: explicitResult.dockerConfig, DOCKER_REGISTRY_AUTH_CONFIG_DIR: explicitResult.dockerConfig } });

  const desktop = await fixture();
  const socket = join(desktop.home, ".docker", "run", "docker.sock");
  await mkdir(join(desktop.home, ".docker", "run"), { recursive: true, mode: 0o700 });
  const shortSocket = join(tmpdir(), `dra-${process.pid}.sock`);
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(shortSocket, resolve);
  });
  try {
    await symlink(shortSocket, socket);
    const result = await createDockerAuthConfig({ env: desktop.env, platform: "darwin" });
    assert.equal(result.dockerHost, `unix://${socket}`);
    assert.match(await readFile(desktop.githubEnv, "utf8"), new RegExp(`^DOCKER_HOST=unix://${socket.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")}$`, "mu"));
    await cleanupDockerAuthConfig({ env: { ...desktop.env, DOCKER_CONFIG: result.dockerConfig, DOCKER_REGISTRY_AUTH_CONFIG_DIR: result.dockerConfig } });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("refuses unknown registries, missing secrets, and two aliases for one Docker Hub auth entry", async () => {
  const unknown = await fixture();
  unknown.env.DOCKER_AUTH_ENTRIES_JSON = JSON.stringify([{ registry: "attacker.example", usernameEnv: "GHCR_USERNAME", passwordEnv: "GHCR_TOKEN" }]);
  await assert.rejects(createDockerAuthConfig({ env: unknown.env, platform: "linux" }), /allowlist/u);
  assert.deepEqual(await readdirSafe(unknown.runnerTemp), []);

  const missing = await fixture();
  delete missing.env.GHCR_TOKEN;
  await assert.rejects(createDockerAuthConfig({ env: missing.env, platform: "linux" }), /missing or empty/u);
  assert.deepEqual(await readdirSafe(missing.runnerTemp), []);

  const aliases = await fixture();
  aliases.env.DOCKER_AUTH_ENTRIES_JSON = JSON.stringify([
    { registry: "docker.io", usernameEnv: "DOCKERHUB_USERNAME", passwordEnv: "DOCKERHUB_TOKEN" },
    { registry: "index.docker.io", usernameEnv: "DOCKERHUB_USERNAME", passwordEnv: "DOCKERHUB_TOKEN" },
  ]);
  await assert.rejects(createDockerAuthConfig({ env: aliases.env, platform: "linux" }), /unique/u);
});

test("cleanup removes only its private task directory and refuses symlinked or changed targets", async () => {
  const context = await fixture();
  const result = await createDockerAuthConfig({ env: context.env, platform: "linux" });
  const neighbor = join(context.runnerTemp, "task-docker-auth-neighbor");
  await mkdir(neighbor, { mode: 0o700 });
  await writeFile(join(neighbor, "keep.txt"), "preserve");
  const cleanupEnv = {
    ...context.env,
    DOCKER_CONFIG: result.dockerConfig,
    DOCKER_REGISTRY_AUTH_CONFIG_DIR: result.dockerConfig,
  };
  assert.deepEqual(await cleanupDockerAuthConfig({ env: cleanupEnv }), { removed: true });
  await assert.rejects(lstat(result.dockerConfig), { code: "ENOENT" });
  assert.equal(await readFile(join(neighbor, "keep.txt"), "utf8"), "preserve");

  const victim = join(context.root, "victim");
  await mkdir(victim, { mode: 0o700 });
  await writeFile(join(victim, ".task-docker-auth-owned"), "owned by scripts/docker-registry-auth.mjs\n", { mode: 0o600 });
  await writeFile(join(victim, "config.json"), "{}\n", { mode: 0o600 });
  const linked = join(context.runnerTemp, "task-docker-auth-symlink");
  await symlink(victim, linked);
  await assert.rejects(cleanupDockerAuthConfig({ env: { ...context.env, DOCKER_REGISTRY_AUTH_CONFIG_DIR: linked, DOCKER_CONFIG: linked } }), /inside the task runner temporary directory|real directory/u);
  await assert.equal(await readFile(join(victim, "config.json"), "utf8"), "{}\n");

  const changed = await createDockerAuthConfig({ env: context.env, platform: "linux" });
  await chmod(join(changed.dockerConfig, "config.json"), 0o644);
  await assert.rejects(cleanupDockerAuthConfig({ env: { ...context.env, DOCKER_REGISTRY_AUTH_CONFIG_DIR: changed.dockerConfig, DOCKER_CONFIG: changed.dockerConfig } }), /private regular file/u);
});

async function readdirSafe(path) {
  const { readdir } = await import("node:fs/promises");
  return readdir(path);
}
