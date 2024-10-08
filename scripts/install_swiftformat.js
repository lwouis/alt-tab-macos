const { exec } = require('child_process');

// Function to execute shell commands
function execCommand(command, callback, errorCallback) {
    exec(command, (error, stdout, stderr) => {
        if (error) {
            if (errorCallback) {
                errorCallback(stderr);
            } else {
                console.error(`Error executing command: ${command}`);
                console.error(`stderr: ${stderr}`);
                process.exit(1);
            }
        } else {
            callback(stdout);
        }
    });
}

// Function to check if a command exists
function commandExists(command, callback) {
    exec(`command -v ${command}`, (error) => {
        callback(!error);
    });
}

// Check if Homebrew is installed
commandExists('brew', (brewExists) => {
    if (brewExists) {
        execCommand('brew --version', (stdout) => {
            console.log(`Homebrew version: ${stdout}`);
            checkSwiftFormat();
        });
    } else {
        console.log('Homebrew is not installed. Installing...');
        // Install Homebrew
        const installBrewCommand = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"';
        execCommand(installBrewCommand, (stdout) => {
            console.log('Homebrew installed successfully.');
            checkSwiftFormat();
        }, (stderr) => {
            console.error('Failed to install Homebrew.');
            console.error(`stderr: ${stderr}`);
        });
    }
});

// Function to check if SwiftFormat is installed
function checkSwiftFormat() {
    commandExists('swiftformat', (exists) => {
        if (exists) {
            console.log('SwiftFormat is already installed.');
        } else {
            console.log('SwiftFormat is not installed. Installing...');
            execCommand('brew install swiftformat', (stdout) => {
                console.log(`SwiftFormat installed: ${stdout}`);
                handleAppleSiliconSymlink();
            });
        }
    });
}

// Function to handle symbolic link for Apple Silicon
function handleAppleSiliconSymlink() {
    execCommand('uname -m', (stdout) => {
        if (stdout.trim() === 'arm64') {
            console.log('Running on Apple Silicon (arm64)');
            // Create symbolic link for Apple Silicon compatibility
            const command = 'ln -sf /opt/homebrew/bin/swiftformat /usr/local/bin/swiftformat';
            execCommand(command, (stdout) => {
                console.log('Symlink created/updated successfully.');
            });
        } else {
            console.log('Not running on Apple Silicon (arm64), no symlink needed.');
        }
    });
}
