# Bash Aliases Configuration
# Managed by bashmin aliases installer
# Last updated: $(date)

# === NAVIGATION & DIRECTORY OPERATIONS ===
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# Enhanced ls aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -ltr'
alias lh='ls -lah'
alias lsa='ls -lah'

# Directory operations
alias mkdir='mkdir -pv'
alias md='mkdir -pv'
alias rmdir='rmdir -v'
alias rd='rmdir -v'

# === DIRECTORIES/VIRTUAL HOSTS (UBUNTU) ===
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

# WSL shortcuts (if applicable)
alias WIN_D="cd /mnt/d/"
alias WIN_C="cd /mnt/c/"
alias WIN_V="cd /mnt/v/"
alias WIN_W="cd /mnt/w/"

# === FILE OPERATIONS ===
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias ln='ln -iv'
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'

# Enhanced file viewing
alias cat='cat -n'
alias less='less -R'
alias more='less'
alias head='head -n 20'
alias tail='tail -n 20'
alias OP_LOG="sudo tail -f *.log"

# File searching
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias find='find 2>/dev/null'

# === SYSTEM INFORMATION ===
alias df='df -h'
alias dfh="df -h"
alias du='du -h'
alias free='free -h'
alias ps='ps auxf'
alias psg='ps aux | grep -v grep | grep -i -E'
alias top='htop'
alias mount='mount | column -t'

# Process management
alias jobs='jobs -l'
alias killall='killall -v'

# === NETWORK & CONNECTIVITY ===
alias ping='ping -c 5'
alias wget='wget -c'
alias curl='curl -L'
alias ports='netstat -tulanp'
alias listening='netstat -tulanp | grep LISTEN'

# Network info
alias myip='curl -s ipinfo.io/ip'
alias localip="ip route get 1 | awk '{print \$NF;exit}'"
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"

# === PACKAGE MANAGEMENT ===
alias apt-update='sudo apt update && sudo apt upgrade'
alias apt-install='sudo apt install'
alias apt-remove='sudo apt remove'
alias apt-search='apt search'
alias apt-show='apt show'
alias apt-list='apt list'
alias sysupd="sudo apt update -y && sudo apt upgrade -y"

# === DEVELOPMENT TOOLS ===
# Git aliases
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gba='git branch -a'
alias gbd='git branch -d'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit -a'
alias gcam='git commit -a -m'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gd='git diff'
alias gds='git diff --staged'
alias gf='git fetch'
alias gl='git log --oneline'
alias gll='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias gp='git push'
alias gpl='git pull'
alias gs='git status'
alias gss='git status -s'
alias gst='git stash'
alias gsta='git stash apply'
alias gstd='git stash drop'
alias gstl='git stash list'
alias gstp='git stash pop'

# Existing git aliases (preserved)
alias gitst="git status"
alias gitbr="git branch --show-current"
alias gitbrall="git branch"
alias gitsha="git rev-parse HEAD"
alias gitrem="git remote -v"
alias gitc="git checkout"
alias gitcb="git checkout -b"
alias gitd="git diff"
alias gitcm="git commit -m"

# Docker aliases
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drmi='docker rmi'
alias drm='docker rm'
alias dexec='docker exec -it'
alias dlogs='docker logs'
alias dstop='docker stop'
alias dstart='docker start'
alias drestart='docker restart'

# === PHP/COMPOSER ===
alias art="/usr/bin/php8.3 artisan"
alias cmp="/usr/bin/php8.3 /usr/bin/composer"
alias mig="/usr/bin/php8.3 artisan migrate"
alias migF="/usr/bin/php8.3 artisan migrate:fresh"
alias artcc="/usr/bin/php8.3 artisan optimize:clear"
alias artdbs="/usr/bin/php8.3 artisan db:seed"
alias artls="/usr/bin/php8.3 artisan route:list"

# PHP version switching
alias sysphp="sudo update-alternatives --set php /usr/bin/php"
alias sysphp84="sudo update-alternatives --set php /usr/bin/php8.4"
alias sysphp83="sudo update-alternatives --set php /usr/bin/php8.3"
alias sysphp82="sudo update-alternatives --set php /usr/bin/php8.2"
alias sysphp74="sudo update-alternatives --set php /usr/bin/php7.4"
alias sysphp73="sudo update-alternatives --set php /usr/bin/php7.3"

# CakePHP Specific
alias ckcc="rm -rf app/tmp/cache/persistent && rm app/tmp/cache/*"
alias ckcc8="rm -rf CakePhp/tmp/cache/persistent && rm CakePhp/tmp/cache/*"

# === NODE.JS/NPM/PNPM ===
alias npmg='npm install -g'
alias npml='npm install'
alias npms='npm start'
alias npmt='npm test'
alias npmr='npm run'
alias npmv='npm version'
alias npmu='npm update'

# PNPM
alias pmi="pnpm i"
alias pmu="pnpm add -g pnpm"
alias pmaud="pnpm audit"
alias pmpub="npm publish"
alias pmpubd="npm publish --dry-run"

# Combined updates
alias wfup="/usr/bin/php8.3 /usr/bin/composer update && pnpm update"
alias wfups="composer update && pnpm update"

# === SERVICE MANAGEMENT ===
alias sysctl='sudo systemctl'
alias sysstart='sudo systemctl start'
alias sysstop='sudo systemctl stop'
alias sysrestart='sudo systemctl restart'
alias sysstatus='sudo systemctl status'
alias sysenable='sudo systemctl enable'
alias sysdisable='sudo systemctl disable'
alias sysreload='sudo systemctl reload'

# Apache/Nginx specific
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

# === BASHMIN SPECIFIC ===
# Quick access to bashmin scripts
alias bashmin='cd /var/www/vhosts/bashmin'
alias bm='cd /var/www/vhosts/bashmin'

# Server management
alias add-vhost-apache='sudo /var/www/vhosts/bashmin/servers/apache2/add-vhost.sh'
alias add-vhost-nginx='sudo /var/www/vhosts/bashmin/servers/nginx/add-vhost.sh'
alias add-vhost-frankenphp='sudo /var/www/vhosts/bashmin/servers/frankenphp/add-vhost.sh'
alias update-hosts='/var/www/vhosts/bashmin/hosts/update-hosts.sh'

# Software installation
alias install-software='/var/www/vhosts/bashmin/software/install.sh'

# Security tools
alias security-scan='/var/www/vhosts/bashmin/security/lynis/run-scan.sh'
alias update-clamav='/var/www/vhosts/bashmin/security/clamav/update.sh'

# Aliases management
alias update-aliases='/var/www/vhosts/bashmin/aliases/self-update.sh'
alias install-aliases='/var/www/vhosts/bashmin/aliases/install.sh'

# === TEXT EDITING ===
alias vi='vim'
alias nano='nano -w'
alias edit='$EDITOR'
alias modh="sudo nano /etc/hosts"

# === UTILITY FUNCTIONS ===
# Quick calculator
alias calc='bc -l'

# Date/time
alias now='date +"%T"'
alias nowdate='date +"%d-%m-%Y"'
alias nowdatetime='date +"%d-%m-%Y %T"'

# History
alias h='history'
alias hgrep='history | grep'

# Quick reload of bash configuration
alias reload='source ~/.bashrc'
alias rebash='source ~/.bashrc'
alias bsrl="source ~/.bashrc"

# Clear screen variants
alias cls='clear'
alias clr='clear'

# === ARCHIVE OPERATIONS ===
alias tar='tar -v'
alias untar='tar -xvf'
alias untargz='tar -xzf'
alias untarbz2='tar -xjf'

# Compression
alias targz='tar -czf'
alias tarbz2='tar -cjf'
alias zip='zip -r'

# === DATABASE ===
alias mysql='mysql --auto-rehash'
alias mysqldump='mysqldump --single-transaction --routines --triggers'

# === SECURITY & PERMISSIONS ===
alias chmodx='chmod +x'
alias chmodr='chmod 644'
alias chmodb='chmod 755'

# === FUNCTION ALIASES ===
# Extract archives
extract() {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)     echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}
alias ex='extract'

# Make directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Quick file search
ff() {
    find . -type f -name "*$1*"
}

# Quick directory search
fd() {
    find . -type d -name "*$1*"
}

# === COLOR SUPPORT ===
# Enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi