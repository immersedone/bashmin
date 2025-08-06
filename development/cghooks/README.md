# Composer Git Hooks Installer

This script automates the installation and configuration of [BrainMaestro/composer-git-hooks](https://github.com/BrainMaestro/composer-git-hooks) for PHP/Composer projects.

## Overview

Composer Git Hooks is a library that allows you to easily manage Git hooks through your `composer.json` file. This installer script streamlines the setup process and provides sensible defaults for common development workflows.

## Features

- ✅ **Automatic Installation**: Installs the package via Composer
- ✅ **Smart Detection**: Detects PHP/Composer projects automatically  
- ✅ **Configuration**: Automatically configures common Git hooks
- ✅ **Custom Scripts**: Copies and uses `.dev/` scripts if available
- ✅ **Intelligent Merging**: Merges with existing `composer.json` configuration
- ✅ **Flexible Options**: Supports both local and global installation
- ✅ **Safety Checks**: Validates requirements and existing installations
- ✅ **Backup Creation**: Creates backups before modifying files
- ✅ **Dry Run Mode**: Test what would happen without making changes

## Requirements

- PHP >= 7.4
- Composer >= 2.0
- Git (for hook functionality)

## Quick Start

```bash
# Install with default settings (recommended)
./install.sh

# Install globally for use across projects
./install.sh --global

# Install in a specific directory
./install.sh --working-dir=/path/to/your/project

# Dry run to see what would happen
./install.sh --dry-run --verbose
```

## Usage

```bash
./install.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --verbose` | Enable verbose output |
| `-d, --dry-run` | Show what would be done without executing |
| `-f, --force` | Force installation even if already present |
| `-g, --global` | Install as global composer package |
| `--production` | Install as production dependency (not dev) |
| `--no-auto-config` | Skip automatic hook configuration |
| `--no-samples` | Skip adding sample hook configurations |
| `--working-dir=DIR` | Target directory for installation |
| `--disable-pre-commit` | Disable pre-commit hook setup |
| `--disable-pre-push` | Disable pre-push hook setup |
| `--enable-post-merge` | Enable post-merge hook setup |
| `--enable-post-checkout` | Enable post-checkout hook setup |

## Default Hook Configuration

The script intelligently configures these hooks:

### With Custom .dev/ Scripts (Preferred)
If `.dev/` directory exists in the installer location, the script will:
- Copy custom hook scripts to your project's `.dev/` directory
- Configure hooks to execute these custom scripts
- Provide Laravel/PHP-optimized hooks with:
  - **Pre-commit**: Pint (PHP CS Fixer) + ESLint
  - **Pre-push**: PHPStan + Pest Architecture tests
  - **Post-merge**: Smart dependency installation based on changed files

### Fallback Default Configuration
If no `.dev/` scripts are found, uses these defaults:

### Pre-commit Hook
- Code style checking (phpcs)
- Static analysis (phpstan)
- Custom validation scripts

### Pre-push Hook  
- Run test suite
- Additional quality checks

### Optional Hooks
- **post-merge**: Install dependencies after merging
- **post-checkout**: Install dependencies after checkout

## Examples

### Basic Installation
```bash
# Navigate to your PHP project
cd /path/to/your/php/project

# Install with defaults
./install.sh
```

### Custom Configuration
```bash
# Install with custom settings
./install.sh \
  --verbose \
  --enable-post-merge \
  --enable-post-checkout \
  --force
```

### Global Installation
```bash
# Install globally for reuse across projects
./install.sh --global

# Then in any PHP project:
cd /path/to/another/project
composer run-script cghooks:add
```

## What Gets Modified

### .dev/ Directory (If Available)
Custom hook scripts are copied to your project:
```
.dev/
├── pre-commit     # Pint + ESLint checks
├── pre-push       # PHPStan + Architecture tests  
└── post-merge     # Smart dependency management
```

### composer.json
The script **merges** (doesn't overwrite) hooks configuration:

```json
{
  "extra": {
    "hooks": {
      "pre-commit": ["./.dev/pre-commit"],
      "pre-push": ["./.dev/pre-push"],
      "post-merge": ["./.dev/post-merge"]
    }
  }
}
```

**Note**: Existing hooks are preserved and new ones are intelligently merged.

### Git Hooks
Physical hook files are created in `.git/hooks/`:
- `pre-commit`
- `pre-push` 
- `post-merge` (if enabled)
- `post-checkout` (if enabled)

## Available Commands After Installation

Once installed, you can use these Composer commands:

```bash
# Install/update hooks
composer run-script cghooks:add

# Update existing hooks
composer run-script cghooks:update

# Remove all hooks
composer run-script cghooks:remove

# List configured hooks
composer run-script cghooks:list
```

## Troubleshooting

### Common Issues

**"No composer.json found"**
- Ensure you're in a PHP/Composer project directory
- Use `--global` flag for global installation

**"Package already installed"**
- Use `--force` flag to reinstall
- Check with `composer show brainmaestro/composer-git-hooks`

**"Git hooks not working"**
- Ensure you're in a Git repository (`git init` if needed)
- Check `.git/hooks/` directory exists
- Verify hook files are executable

### Debug Mode
```bash
# Run with verbose output for debugging
./install.sh --verbose --dry-run
```

## Integration with CI/CD

The installed hooks work great with CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Install dependencies
  run: composer install

- name: Setup Git hooks  
  run: composer run-script cghooks:add

- name: Run pre-commit checks
  run: composer run-script phpcs && composer run-script phpstan
```

## Customization

### Custom .dev/ Hook Scripts

After installation, you can customize the hook behavior by editing the `.dev/` scripts:

```bash
# Edit pre-commit behavior
nano .dev/pre-commit

# Edit pre-push behavior  
nano .dev/pre-push

# Edit post-merge behavior
nano .dev/post-merge
```

Example `.dev/pre-commit` script:
```bash
#!/bin/bash
echo '\n\n\033[0;36mcghooks - Pre-Commit: \033[0m \n'
echo 'Committing as: \033[0;32m'$(git config user.name) '('$(git config user.email)') \033[0m\n'

echo '\n\033[0;35mRunning Pint (PHP CS Fixer): \033[0m\n'
vendor/bin/pint

echo '\n\033[0;35mRunning ESLint: \033[0m\n'
pnpm run lint:fix
```

### Custom Hook Commands

Edit your `composer.json` after installation:

```json
{
  "extra": {
    "hooks": {
      "pre-commit": [
        "vendor/bin/php-cs-fixer fix --dry-run --diff",
        "vendor/bin/phpstan analyse --level=8 src/",
        "vendor/bin/phpunit --testsuite=unit"
      ]
    }
  }
}
```

### Project-specific Scripts

The installer can automatically add these to your `composer.json` scripts section:

```json
{
  "scripts": {
    "phpcs": "vendor/bin/phpcs --standard=PSR12 src/",
    "phpstan": "vendor/bin/phpstan analyse src/",
    "test": "vendor/bin/phpunit",
    "pint": "vendor/bin/pint",
    "pest": "vendor/bin/pest"
  }
}
```

## Best Practices

1. **Start Simple**: Begin with basic pre-commit and pre-push hooks
2. **Keep Hooks Fast**: Avoid long-running operations in pre-commit
3. **Use Scripts**: Define reusable commands in composer.json scripts
4. **Test Hooks**: Verify hooks work before pushing to shared repositories
5. **Document**: Keep team members informed about hook requirements

## Related Tools

Consider pairing with these complementary tools:
- [PHP_CodeSniffer](https://github.com/squizlabs/PHP_CodeSniffer) for code style
- [PHPStan](https://github.com/phpstan/phpstan) for static analysis  
- [PHPUnit](https://github.com/sebastianbergmann/phpunit) for testing
- [PHP-CS-Fixer](https://github.com/FriendsOfPHP/PHP-CS-Fixer) for code formatting

## Support

- 📖 [Composer Git Hooks Documentation](https://github.com/BrainMaestro/composer-git-hooks)
- 🐛 [Report Issues](https://github.com/BrainMaestro/composer-git-hooks/issues)
- 💡 [Feature Requests](https://github.com/BrainMaestro/composer-git-hooks/discussions)

---

**Happy coding!** 🚀
