#!/usr/bin/env node

import { constants, lstat, mkdir, mkdtemp, open, readFile, realpath, rm, stat, symlink, chmod } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

const ownedPrefix = "task-docker-auth-";
const markerName = ".task-docker-auth-owned";
const markerValue = "owned by scripts/docker-registry-auth.mjs\n";
const registryAuthKeys = new Map([
  ["ghcr.io", "ghcr.io"],
  ["cr.yandex", "cr.yandex"],
  ["registry.yandexcloud.net", "registry.yandexcloud.net"],
  ["docker.io", "https://index.docker.io/v1/"],
  ["index.docker.io", "https://index.docker.io/v1/"],
]);

function fail(message) {
  throw new Error(message);
}

function assertOwnedPath(path, expectedParent, label) {
  if (!isAbsolute(path)) fail(`${label} must be an absolute path.`);
  const normalized = resolve(path);
  const rel = relative(expectedParent, normalized);
  if (!rel || rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
    fail(`${label} must be inside the task runner temporary directory.`);
  }
  return normalized;
}

async function assertPrivateDirectory(path, expectedUid, label) {
  const entry = await lstat(path);
  if (!entry.isDirectory() || entry.isSymbolicLink()) fail(`${label} must be a real directory.`);
  if (expectedUid !== undefined && entry.uid !== expectedUid) fail(`${label} is owned by another user.`);
  if ((entry.mode & 0o077) !== 0) fail(`${label} permissions must be 0700.`);
  if (await realpath(path) !== resolve(path)) fail(`${label} resolves outside its expected location.`);
  return entry;
}

async function appendGithubEnvironment(path, values) {
  if (!path || !isAbsolute(path)) fail("GITHUB_ENV must be an absolute path.");
  const entry = await lstat(path);
  if (!entry.isFile() || entry.isSymbolicLink()) fail("GITHUB_ENV must be a regular file.");
  if (typeof process.getuid === "function" && entry.uid !== process.getuid()) fail("GITHUB_ENV is owned by another user.");
  for (const [name, value] of Object.entries(values)) {
    if (/[\r\n]/u.test(value)) fail(`${name} contains an unsafe line break.`);
  }
  const contents = Object.entries(values).map(([name, value]) => `${name}=${value}\n`).join("");
  const handle = await open(path, constants.O_WRONLY | constants.O_APPEND | (constants.O_NOFOLLOW ?? 0));
  try {
    await handle.writeFile(contents, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
}

function parseAuthEntries(env) {
  let entries;
  try {
    entries = JSON.parse(env.DOCKER_AUTH_ENTRIES_JSON ?? "");
  } catch {
    fail("DOCKER_AUTH_ENTRIES_JSON must contain a JSON array of environment variable references.");
  }
  if (!Array.isArray(entries) || entries.length === 0) fail("At least one Docker registry credential entry is required.");
  const seen = new Set();
  return entries.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) fail("Docker registry entries must be objects.");
    const registry = typeof entry.registry === "string" ? entry.registry.toLowerCase() : "";
    const usernameEnv = entry.usernameEnv;
    const passwordEnv = entry.passwordEnv;
    const authKey = registryAuthKeys.get(registry);
    if (!authKey || registry !== entry.registry) fail("Docker registry is not in the supported registry allowlist.");
    if (!/^[A-Z][A-Z0-9_]*$/u.test(usernameEnv ?? "") || !/^[A-Z][A-Z0-9_]*$/u.test(passwordEnv ?? "")) {
      fail("Docker credential entries must reference environment variable names.");
    }
    if (seen.has(authKey)) fail("Docker registry entries must be unique.");
    seen.add(authKey);
    const username = env[usernameEnv];
    const password = env[passwordEnv];
    if (typeof username !== "string" || !username || username.includes(":") || /[\r\n]/u.test(username)) {
      fail(`Docker username environment variable ${usernameEnv} is missing or invalid.`);
    }
    if (typeof password !== "string" || !password) fail(`Docker password environment variable ${passwordEnv} is missing or empty.`);
    return { registry, authKey, username, password };
  });
}

export function buildxPluginCandidates(env = process.env) {
  const home = env.HOME || homedir();
  const config = env.DOCKER_CONFIG || join(home, ".docker");
  return [
    join(config, "cli-plugins", "docker-buildx"),
    join(home, ".docker", "cli-plugins", "docker-buildx"),
    "/usr/local/lib/docker/cli-plugins/docker-buildx",
    "/usr/local/libexec/docker/cli-plugins/docker-buildx",
    "/usr/lib/docker/cli-plugins/docker-buildx",
    "/usr/libexec/docker/cli-plugins/docker-buildx",
    "/opt/homebrew/lib/docker/cli-plugins/docker-buildx",
    "/Applications/Docker.app/Contents/Resources/cli-plugins/docker-buildx",
  ];
}

async function linkTrustedBuildxPlugin(configDir, env) {
  const pluginDir = join(configDir, "cli-plugins");
  await mkdir(pluginDir, { mode: 0o700 });
  await chmod(pluginDir, 0o700);
  const destination = join(pluginDir, "docker-buildx");
  for (const candidate of buildxPluginCandidates(env)) {
    try {
      const installed = await realpath(candidate);
      const executable = await stat(installed);
      if (!executable.isFile() || (executable.mode & 0o111) === 0) continue;
      if (typeof process.getuid === "function" && executable.uid !== process.getuid() && executable.uid !== 0) continue;
      if ((executable.mode & 0o022) !== 0) continue;
      await symlink(installed, destination);
      return destination;
    } catch (error) {
      if (error?.code === "EEXIST") return destination;
    }
  }
  // setup-buildx-action can install Buildx into this private config when no
  // system plugin exists. Do not fall back to or modify the user's config.
  return undefined;
}

async function runnerTempDirectory(env) {
  if (!env.RUNNER_TEMP || !isAbsolute(env.RUNNER_TEMP)) fail("RUNNER_TEMP must be an absolute path.");
  const path = resolve(env.RUNNER_TEMP);
  const entry = await lstat(path);
  if (!entry.isDirectory() || entry.isSymbolicLink()) fail("RUNNER_TEMP must be a real directory.");
  if (typeof process.getuid === "function" && entry.uid !== process.getuid()) fail("RUNNER_TEMP is owned by another user.");
  // Canonicalize parent aliases such as macOS /tmp -> /private/tmp while
  // still refusing a symlink at RUNNER_TEMP itself.
  return realpath(path);
}

async function resolveDockerHost(env, platform) {
  if (typeof env.DOCKER_HOST === "string" && env.DOCKER_HOST.trim()) return undefined;
  if (platform !== "darwin") return undefined;
  const socket = join(env.HOME || homedir(), ".docker", "run", "docker.sock");
  try {
    if ((await stat(socket)).isSocket()) return `unix://${socket}`;
  } catch {
    // Report an actionable failure without reading or changing the user's config.
  }
  fail(`Docker Desktop socket is unavailable at ${socket}.`);
}

export async function createDockerAuthConfig({ env = process.env, platform = process.platform } = {}) {
  if (!env.GITHUB_ENV || !isAbsolute(env.GITHUB_ENV)) fail("GITHUB_ENV is required to pass the private Docker config to later steps.");
  const credentials = parseAuthEntries(env);
  const runnerTemp = await runnerTempDirectory(env);
  const dockerHost = await resolveDockerHost(env, platform);
  let root;
  try {
    root = await mkdtemp(join(runnerTemp, ownedPrefix));
    await chmod(root, 0o700);
    await assertPrivateDirectory(root, process.getuid?.(), "Task Docker config directory");
    const markerPath = join(root, markerName);
    const markerHandle = await open(markerPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600);
    try {
      await markerHandle.writeFile(markerValue, "utf8");
      await markerHandle.sync();
    } finally {
      await markerHandle.close();
    }

    const configPath = join(root, "config.json");
    const auths = Object.fromEntries(credentials.map(({ authKey, username, password }) => [
      authKey,
      { auth: Buffer.from(`${username}:${password}`, "utf8").toString("base64") },
    ]));
    const configHandle = await open(configPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0), 0o600);
    try {
      await configHandle.writeFile(`${JSON.stringify({ auths })}\n`, "utf8");
      await configHandle.chmod(0o600);
      await configHandle.sync();
    } finally {
      await configHandle.close();
    }

    await linkTrustedBuildxPlugin(root, env);
    const configStat = await lstat(configPath);
    if (!configStat.isFile() || configStat.isSymbolicLink() || configStat.uid !== process.getuid?.() || (configStat.mode & 0o777) !== 0o600) {
      fail("Task Docker config file did not retain private ownership and permissions.");
    }
    const envValues = {
      DOCKER_CONFIG: root,
      DOCKER_REGISTRY_AUTH_CONFIG_DIR: root,
    };
    if (dockerHost) envValues.DOCKER_HOST = dockerHost;
    await appendGithubEnvironment(env.GITHUB_ENV, envValues);
    return { dockerConfig: root, dockerHost, registries: credentials.map(({ registry }) => registry) };
  } catch (error) {
    if (root) await rm(root, { recursive: true, force: true });
    throw error;
  } finally {
    for (const credential of credentials) {
      credential.password = "";
      credential.username = "";
    }
  }
}

async function assertOwnedConfigRoot(path, runnerTemp, expectedUid) {
  const root = assertOwnedPath(path, runnerTemp, "Task Docker config directory");
  if (basename(root).startsWith(ownedPrefix) !== true) fail("Task Docker config directory name is not recognized.");
  await assertPrivateDirectory(root, expectedUid, "Task Docker config directory");
  const markerPath = join(root, markerName);
  const markerStat = await lstat(markerPath);
  if (!markerStat.isFile() || markerStat.isSymbolicLink() || markerStat.uid !== expectedUid || (markerStat.mode & 0o777) !== 0o600) {
    fail("Task Docker config ownership marker is invalid.");
  }
  if (await readFile(markerPath, "utf8") !== markerValue) fail("Task Docker config ownership marker contents are invalid.");
  const configPath = join(root, "config.json");
  const configStat = await lstat(configPath);
  if (!configStat.isFile() || configStat.isSymbolicLink() || configStat.uid !== expectedUid || (configStat.mode & 0o777) !== 0o600) {
    fail("Task Docker config file is not a private regular file.");
  }
  return root;
}

export async function cleanupDockerAuthConfig({ env = process.env } = {}) {
  const path = env.DOCKER_REGISTRY_AUTH_CONFIG_DIR;
  if (!path) return { removed: false };
  const runnerTemp = await runnerTempDirectory(env);
  const root = await assertOwnedConfigRoot(path, runnerTemp, process.getuid?.());
  if (env.DOCKER_CONFIG && resolve(env.DOCKER_CONFIG) !== root) fail("DOCKER_CONFIG no longer points to the owned task directory; refusing cleanup.");
  await rm(root, { recursive: true, force: false });
  return { removed: true };
}

async function main() {
  const command = process.argv[2];
  if (command === "create") {
    const result = await createDockerAuthConfig();
    console.log(`Docker registry auth is scoped to a private task config (${result.registries.join(", ")}).`);
    return;
  }
  if (command === "cleanup") {
    const result = await cleanupDockerAuthConfig();
    if (result.removed) console.log("Removed the private task Docker config.");
    return;
  }
  fail("Usage: node scripts/docker-registry-auth.mjs <create|cleanup>.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "Docker registry authentication setup failed.");
    process.exitCode = 1;
  });
}
