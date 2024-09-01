const { exec } = require('child_process');

// Function to execute shell commands
function execCommand(command, callback) {
    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error executing command: ${command}`);
            console.error(`stderr: ${stderr}`);
            process.exit(1);
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
execCommand('brew --version', (stdout) => {
    console.log(`Homebrew version: ${stdout}`);

    // Check if SwiftFormat is already installed
    commandExists('swiftformat', (exists) => {
        if (exists) {
            console.log('SwiftFormat is already installed.');
            // Update SwiftFormat if it is already installed
            // execCommand('brew upgrade swiftformat', (stdout) => {
            //     console.log(`SwiftFormat updated: ${stdout}`);
            //     handleAppleSiliconSymlink();
            // });
        } else {
            console.log('SwiftFormat is not installed. Installing...');
            // Install SwiftFormat if it is not installed
            execCommand('brew install swiftformat', (stdout) => {
                console.log(`SwiftFormat installed: ${stdout}`);
                handleAppleSiliconSymlink();
            });
        }
    });
});

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
