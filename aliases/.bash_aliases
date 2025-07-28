# Directories (WSL)
alias WIN_D="cd /mnt/d/"
alias WIN_C="cd /mnt/c/"
alias WIN_V="cd /mnt/v/"
alias WIN_W="cd /mnt/w/"

# Directories/Virtual Hosts (Ubuntu)
alias WWW="cd /var/www/vhosts"
alias LOG_DIR="cd /var/log"
alias LOG_NGINX="cd /var/log/nginx"
alias LOG_APACHE="cd /var/log/apache2"
alias DR_NG="cd /etc/nginx"
alias DR_NG_STA="cd /etc/nginx/sites-available"
alias DR_NG_STE="cd /etc/nginx/sites-enabled"
alias DR_AP="cd /etc/apache2"
alias DR_AP_STA="cd /etc/apache2/sites-available"
alias DR_AP_STE="cd /etc/apache2/sites-enabled"
alias DR_PHP="cd /etc/php"

# Logging
alias OP_LOG="sudo tail -f *.log"

# PHP/Composer
alias art="/usr/bin/php8.3 artisan"
alias cmp="/usr/bin/php8.3 /usr/bin/composer"
alias mig="/usr/bin/php8.3 artisan migrate"
alias migF="/usr/bin/php8.3 artisan migrate:fresh"
alias artcc="/usr/bin/php8.3 artisan optimize:clear"
alias artdbs="/usr/bin/php8.3 artisan db:seed"
alias artls="/usr/bin/php8.3 artisan route:list"

# CakePHP Specific
alias ckcc="rm -rf app/tmp/cache/persistent && rm app/tmp/cache/*"
alias ckcc8="rm -rf CakePhp/tmp/cache/persistent && rm CakePhp/tmp/cache/*"

# Git
alias gitst="git status"
alias gitbr="git branch --show-current"
alias gitbrall="git branch"
alias gitsha="git rev-parse HEAD"
alias gitrem="git remote -v"
alias gitc="git checkout"
alias gitcb="git checkout -b"
alias gitd="git diff"
alias gitcm="git commit -m"

# Elastic Beanstalk
alias ebll="eb list"

# PNPM/Composer
alias wfup="/usr/bin/php8.3 /usr/bin/composer update && pnpm update"
alias wfups="composer update && pnpm update"

# NPM/PNPM
alias pmi="pnpm i"
alias pmu="pnpm add -g pnpm"
alias pmaud="pnpm audit"
alias pmpub="npm publish"
alias pmpubd="npm publish --dry-run"

# System Package Manger/Shortcuts (Ubuntu/Debian)
alias bsrl="source ~/.bashrc"
alias sysupd="sudo apt update -y && sudo apt upgrade -y"
alias modh="sudo nano /etc/hosts"
alias sysphp="sudo update-alternatives --set php /usr/bin/php"
alias sysphp83="sudo update-alternatives --set php /usr/bin/php8.3"
alias sysphp82="sudo update-alternatives --set php /usr/bin/php8.2"
alias sysphp74="sudo update-alternatives --set php /usr/bin/php7.4"
alias sysphp73="sudo update-alternatives --set php /usr/bin/php7.3"

# Shortcuts
alias ll="ls -la"
alias ..="cd ../"
alias ...="cd ../../"
alias ....="cd ../../../"
alias .....="cd ../../../../"
alias dfh="df -h"

# Service/Server Shortcuts
alias apcf="sudo apache2ctl -t"
alias ngcf="sudo nginx -t"
alias aprs="sudo service apache2 restart"
alias aprl="sudo service apache2 reload"
alias ngrs="sudo service nginx restart"
alias ngrl="sudo service nginx reload"
alias phprs="sudo service php8.3-fpm restart"
alias phprl="sudo service php8.3-fpm reload"
alias stackll="sudo service --status-all"
alias stackrs="sudo service apache2 restart && sudo service nginx restart && sudo service php8.3-fpm restart"
alias stackrl="sudo service apache2 reload && sudo service nginx reload && sudo service php8.3-fpm reload"