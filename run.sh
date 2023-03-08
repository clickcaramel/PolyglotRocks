#!/bin/bash

if [[ $(uname -s) == "Darwin" ]]; then
    JQ_BINARY_NAME="jq-osx-amd64"
elif [[ $(uname -s) == "Linux" ]]; then
    JQ_BINARY_NAME="jq-linux64"
else
    echo "Error: Operating system is not supported"
    exit 1
fi

if [[ " $* " =~ " --install " ]]; then
    INSTALL=true
else
    INSTALL=false
fi

if [ "$INSTALL" == true ]; then
    DEFAULT_INSTALL_DIR="$HOME/.polyglot"    
else
    DEFAULT_INSTALL_DIR=".polyglot"
fi

SCRIPT_INSTALL_PATH="$DEFAULT_INSTALL_DIR/polyglot"
JQ_INSTALL_PATH="$DEFAULT_INSTALL_DIR/lib/$JQ_BINARY_NAME"
mkdir -p "$DEFAULT_INSTALL_DIR/lib"

NEED_TO_DOWNLOAD=false
if [ "$INSTALL" == false ]; then
    if [ ! -f "$SCRIPT_INSTALL_PATH" ] || [ ! -f "$JQ_INSTALL_PATH" ]; then
        echo "PolyglotRocks files are missing. Need to download them."
        echo
        NEED_TO_DOWNLOAD=true
    fi
else
    NEED_TO_DOWNLOAD=true
fi

if [ "$NEED_TO_DOWNLOAD" == true ]; then
    curl -s "https://raw.githubusercontent.com/clickcaramel/PolyglotRocks/main/bin/polyglot" -o "$SCRIPT_INSTALL_PATH"
    curl -s "https://raw.githubusercontent.com/clickcaramel/PolyglotRocks/main/bin/lib/$JQ_BINARY_NAME" -o "$JQ_INSTALL_PATH"
fi

chmod +x "$SCRIPT_INSTALL_PATH"
chmod +x "$JQ_INSTALL_PATH"


if [ "$INSTALL" == true ]; then
    echo "The script is installed to $SCRIPT_INSTALL_PATH"
    read -p "Do you want to add it to the PATH to be able to run from anywhere? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Add the polyglot directory to the PATH variable in Bash
        if [ -f "$HOME/.bashrc" ]; then
            if ! grep -q "export PATH=\"\$HOME/.polyglot:\$PATH\"" "$HOME/.bashrc"; then
                echo 'export PATH="$HOME/.polyglot:$PATH"' >> "$HOME/.bashrc"
                echo "The .bashrc profile has been updated"
            fi
        fi

        # Add the polyglot directory to the PATH variable in Zsh
        if [ -f "$HOME/.zshrc" ]; then
            if ! grep -q "export PATH=\"\$HOME/.polyglot:\$PATH\"" "$HOME/.zshrc"; then
                echo 'export PATH="$HOME/.polyglot:$PATH"' >> "$HOME/.zshrc"
                echo "The .zshrc profile has been updated"
            fi
        fi
    fi
else
    echo "Automatically starting PolyglotRocks..."
    echo
    $SCRIPT_INSTALL_PATH "$@"
fi
