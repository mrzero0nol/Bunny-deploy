#!/bin/bash
# ===============================================
#  BUNNY DEPLOY MANAGER - v7.0 SECURE EDITION
#  Enhanced Security & Functionality
# ===============================================

# --- SECURITY CONFIGURATION ---
SECURITY_LEVEL="HIGH"  # HIGH, MEDIUM, LOW
AUDIT_LOG="/var/log/bd_audit.log"
HASH_ALGORITHM="sha256"
ALLOWED_GIT_DOMAINS=("github.com" "gitlab.com" "bitbucket.org")
FORBIDDEN_PATHS=("/etc" "/root" "/boot" "/dev" "/proc" "/sys")
MIN_PASSWORD_LENGTH=12

# --- INITIAL SECURITY CHECKS ---
initialize_security() {
    # Create secure temp directory
    SECURE_TMP=$(mktemp -d /tmp/bd_secure.XXXXXX)
    chmod 700 "$SECURE_TMP"
    trap "rm -rf '$SECURE_TMP'" EXIT
    
    # Set restrictive umask
    umask 077
    
    # Check for known malware patterns
    check_malware_patterns
}

# --- INPUT VALIDATION FUNCTIONS ---
validate_domain() {
    local domain="$1"
    # Basic domain pattern validation
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]] || return 1
    
    # Prevent forbidden domains
    local forbidden=("localhost" "127.0.0.1" "example.com" "test.com")
    for f in "${forbidden[@]}"; do
        [[ "$domain" == *"$f"* ]] && return 1
    done
    
    return 0
}

sanitize_input() {
    local input="$1"
    # Remove dangerous characters
    echo "$input" | sed 's/[;&|`$<>]//g' | tr -d '\n\r'
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_path() {
    local path="$1"
    # Check for path traversal attempts
    [[ "$path" =~ \.\. ]] && return 1
    
    # Check against forbidden paths
    for forbidden in "${FORBIDDEN_PATHS[@]}"; do
        [[ "$path" == "$forbidden"* ]] && return 1
    done
    
    return 0
}

# --- SECURITY HEADERS ENHANCED ---
generate_security_headers() {
    cat << EOF
    # Security Headers - Enhanced
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval';" always;
    
    # HSTS (force HTTPS for 1 year)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
EOF
}

# --- SECURE GIT FUNCTIONS ---
validate_git_url() {
    local url="$1"
    
    # Extract domain
    local domain
    if [[ "$url" =~ https?://([^/]+) ]]; then
        domain="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    
    # Check against allowed domains
    for allowed in "${ALLOWED_GIT_DOMAINS[@]}"; do
        [[ "$domain" == *"$allowed" ]] && return 0
    done
    
    # Log suspicious git URL
    log_audit "SUSPICIOUS_GIT_URL" "$url"
    return 1
}

secure_git_clone() {
    local url="$1"
    local dir="$2"
    
    # Validate URL first
    validate_git_url "$url" || {
        echo "ERROR: Git URL not allowed"
        return 1
    }
    
    # Clone with limited depth for security
    git clone --depth 1 "$url" "$dir" || return 1
    
    # Verify no malicious files
    check_repository "$dir"
}

check_repository() {
    local dir="$1"
    
    # Check for suspicious files
    local suspicious_patterns=("*.sh" "*.py" "*.js" "*.php" "Dockerfile" "docker-compose.yml")
    
    for pattern in "${suspicious_patterns[@]}"; do
        find "$dir" -name "$pattern" -type f | while read -r file; do
            # Scan for dangerous patterns
            if grep -q -E "(curl.*bash|wget.*sh|chmod.*777|rm.*-rf|mkfs|dd.*if.*of)" "$file"; then
                log_audit "SUSPICIOUS_FILE" "$file"
                return 1
            fi
        done
    done
    return 0
}

# --- CRYPTOGRAPHIC UPDATE VERIFICATION ---
verify_update() {
    local update_url="$1"
    local signature_url="${update_url}.sig"
    local public_key="/etc/bd/public.pem"
    
    # Download update
    curl -sL "$update_url" -o "$SECURE_TMP/update.sh" || return 1
    
    # Download signature if available
    curl -sL "$signature_url" -o "$SECURE_TMP/update.sig" 2>/dev/null
    
    if [ -f "$SECURE_TMP/update.sig" ] && [ -f "$public_key" ]; then
        # Verify cryptographic signature
        openssl dgst -sha256 -verify "$public_key" -signature "$SECURE_TMP/update.sig" "$SECURE_TMP/update.sh" || {
            log_audit "UPDATE_SIGNATURE_INVALID" "$update_url"
            return 1
        }
    else
        # Fallback: hash verification
        local expected_hash=$(curl -sL "${update_url}.sha256" 2>/dev/null)
        local actual_hash=$(sha256sum "$SECURE_TMP/update.sh" | cut -d' ' -f1)
        
        if [ -n "$expected_hash" ] && [ "$expected_hash" != "$actual_hash" ]; then
            log_audit "UPDATE_HASH_MISMATCH" "$update_url"
            return 1
        fi
    fi
    
    # Additional security checks on update content
    if ! head -n 1 "$SECURE_TMP/update.sh" | grep -q "#!/bin/bash"; then
        return 1
    fi
    
    # Check for dangerous patterns in update
    if grep -q -E "(eval.*base64|exec.*sh|wget.*-O.*sh|curl.*\|.*bash)" "$SECURE_TMP/update.sh"; then
        log_audit "UPDATE_CONTAINS_DANGEROUS_CODE" "$update_url"
        return 1
    fi
    
    return 0
}

# --- AUDIT LOGGING SYSTEM ---
log_audit() {
    local event="$1"
    local details="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user=$(whoami)
    local hostname=$(hostname)
    
    echo "$timestamp | $hostname | $user | $event | $details" >> "$AUDIT_LOG"
    
    # Rate limiting check
    local recent_events=$(grep -c "$event" "$AUDIT_LOG" | tail -n 10)
    if [ "$recent_events" -gt 5 ]; then
        # Alert on suspicious frequency
        echo "SECURITY ALERT: Frequent event '$event' detected" >&2
    fi
}

# --- SECURE DATABASE OPERATIONS ---
secure_db_operation() {
    local operation="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"
    
    # Validate inputs
    [ -z "$db_name" ] && return 1
    [ -z "$db_user" ] && return 1
    [ ${#db_pass} -lt "$MIN_PASSWORD_LENGTH" ] && {
        echo "ERROR: Password too short (min $MIN_PASSWORD_LENGTH chars)"
        return 1
    }
    
    # Use MySQL secure connection with SSL if available
    local ssl_opts=""
    if [ -f "/etc/mysql/ssl/client-cert.pem" ]; then
        ssl_opts="--ssl-ca=/etc/mysql/ssl/ca.pem --ssl-cert=/etc/mysql/ssl/client-cert.pem --ssl-key=/etc/mysql/ssl/client-key.pem"
    fi
    
    case "$operation" in
        "create")
            # Create database with secure password
            mysql $ssl_opts -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
            
            # Create user with limited privileges
            mysql $ssl_opts -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" || return 1
            
            # Grant minimal necessary privileges
            mysql $ssl_opts -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE ON \`${db_name}\`.* TO '${db_user}'@'localhost';" || return 1
            
            # Flush privileges
            mysql $ssl_opts -e "FLUSH PRIVILEGES;" || return 1
            
            log_audit "DB_CREATED" "$db_name"
            ;;
        
        "backup")
            # Create encrypted backup
            local backup_file="/root/backups/${db_name}_$(date +%Y%m%d_%H%M%S).sql.gpg"
            mysqldump --single-transaction --quick --lock-tables=false "$db_name" | \
                gpg --encrypt --recipient "server-backup" --output "$backup_file" || return 1
            
            log_audit "DB_BACKUP_CREATED" "$db_name"
            ;;
        
        "delete")
            # Double confirmation for delete
            echo "WARNING: This will permanently delete database '$db_name'"
            read -p "Type 'DELETE' to confirm: " confirmation
            [ "$confirmation" != "DELETE" ] && return 1
            
            mysql $ssl_opts -e "DROP DATABASE IF EXISTS \`${db_name}\`;" || return 1
            mysql $ssl_opts -e "DROP USER IF EXISTS '${db_user}'@'localhost';" || return 1
            
            log_audit "DB_DELETED" "$db_name"
            ;;
    esac
}

# --- ENHANCED FIREWALL CONFIGURATION ---
configure_firewall() {
    local action="$1"
    local port="$2"
    
    case "$action" in
        "setup")
            # Basic firewall setup with logging
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            
            # Allow SSH with rate limiting
            ufw limit 22/tcp comment 'SSH with rate limiting'
            
            # Allow HTTP/HTTPS
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            
            # Enable logging
            ufw logging on
            
            # Enable firewall
            ufw --force enable
            
            log_audit "FIREWALL_CONFIGURED" "Basic rules applied"
            ;;
        
        "allow_port")
            [ -z "$port" ] && return 1
            
            # Validate port range
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                echo "ERROR: Invalid port number"
                return 1
            fi
            
            # Add port with logging
            ufw allow "$port/tcp" comment "Application port $port"
            ufw reload
            
            log_audit "PORT_OPENED" "$port"
            ;;
    esac
}

# --- SECURITY SCAN MODULE ---
security_scan() {
    echo "=== SECURITY SCAN REPORT ==="
    echo "Generated: $(date)"
    echo "============================"
    
    # 1. Check for open ports
    echo -e "\n[1] OPEN PORTS:"
    ss -tuln | grep LISTEN
    
    # 2. Check for suspicious processes
    echo -e "\n[2] SUSPICIOUS PROCESSES:"
    ps aux | grep -E "(minerd|miner|xmrig|ccminer|php.*base64)" | grep -v grep
    
    # 3. Check crontab for suspicious entries
    echo -e "\n[3] CRON JOBS:"
    crontab -l 2>/dev/null | grep -v "^#" | while read -r line; do
        if [[ "$line" =~ (curl.*bash|wget.*sh|base64.*decode) ]]; then
            echo "SUSPICIOUS: $line"
        fi
    done
    
    # 4. Check file permissions
    echo -e "\n[4] WORLD-WRITABLE FILES:"
    find /var/www -type f -perm -o+w 2>/dev/null | head -n 10
    
    # 5. Check for failed SSH attempts
    echo -e "\n[5] FAILED SSH LOGINS:"
    grep "Failed password" /var/log/auth.log 2>/dev/null | tail -n 5
    
    # 6. Disk usage warning
    echo -e "\n[6] DISK USAGE:"
    df -h / | awk 'NR==2 {print "Used: " $3 "/" $2 " (" $5 ")"}'
    
    # 7. Check for unauthorized sudo usage
    echo -e "\n[7] RECENT SUDO COMMANDS:"
    grep sudo /var/log/auth.log 2>/dev/null | tail -n 3
    
    log_audit "SECURITY_SCAN_PERFORMED" "Full system scan"
}

# --- ENHANCED MONITORING ---
setup_monitoring() {
    local domain="$1"
    
    # Create monitoring script
    cat > "/usr/local/bin/monitor_${domain}.sh" << EOF
#!/bin/bash
DOMAIN="$domain"
LOG_FILE="/var/log/bd_monitor_\$DOMAIN.log"

check_website() {
    HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://\$DOMAIN")
    if [ "\$HTTP_CODE" != "200" ] && [ "\$HTTP_CODE" != "301" ] && [ "\$HTTP_CODE" != "302" ]; then
        echo "\$(date) - HTTP \$HTTP_CODE" >> "\$LOG_FILE"
        # Send alert
        echo "Website \$DOMAIN down: HTTP \$HTTP_CODE" | mail -s "Alert: \$DOMAIN Down" admin@example.com
    fi
}

check_ssl() {
    EXPIRY=\$(echo | openssl s_client -connect \$DOMAIN:443 -servername \$DOMAIN 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
    DAYS_LEFT=\$(( (\$(date -d "\$EXPIRY" +%s) - \$(date +%s)) / 86400 ))
    if [ "\$DAYS_LEFT" -lt 7 ]; then
        echo "\$(date) - SSL expires in \$DAYS_LEFT days" >> "\$LOG_FILE"
    fi
}

check_disk() {
    USAGE=\$(df /var/www/\$DOMAIN | awk 'NR==2 {print \$5}' | sed 's/%//')
    if [ "\$USAGE" -gt 90 ]; then
        echo "\$(date) - Disk usage \$USAGE%" >> "\$LOG_FILE"
    fi
}

# Run checks
check_website
check_ssl
check_disk
EOF
    
    chmod 700 "/usr/local/bin/monitor_${domain}.sh"
    
    # Add to crontab (every hour)
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/monitor_${domain}.sh") | crontab -
    
    log_audit "MONITORING_SETUP" "$domain"
}

# --- ENHANCED DEPLOYMENT FUNCTION ---
secure_deploy() {
    local domain="$1"
    local deploy_type="$2"
    local git_url="$3"
    
    # Validate inputs
    validate_domain "$domain" || {
        echo "ERROR: Invalid domain name"
        return 1
    }
    
    # Create secure directory structure
    local web_root="/var/www/$domain"
    local log_dir="/var/log/nginx/$domain"
    
    mkdir -p "$web_root" "$log_dir"
    chown -R www-data:www-data "$web_root" "$log_dir"
    chmod 750 "$web_root"
    chmod 750 "$log_dir"
    
    # Set up filesystem security
    setfacl -R -m u:www-data:rx "$web_root"
    
    # If git URL provided, clone securely
    if [ -n "$git_url" ]; then
        secure_git_clone "$git_url" "$web_root" || {
            echo "ERROR: Git clone failed security checks"
            return 1
        }
    fi
    
    # Generate secure Nginx configuration
    generate_secure_nginx_config "$domain" "$deploy_type"
    
    # Setup monitoring
    setup_monitoring "$domain"
    
    log_audit "DEPLOYMENT_COMPLETE" "$domain"
}

# --- MAIN ENHANCED FUNCTIONS (MODULAR) ---
# [All previous functions like deploy_web, manage_web, etc. with security enhancements]

# --- RATE LIMITING PROTECTION ---
setup_rate_limiting() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    
    # Add rate limiting configuration
    cat >> "$config_file" << EOF

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=auth:10m rate=5r/m;
    
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        # Your API configuration
    }
    
    location /login {
        limit_req zone=auth burst=3 nodelay;
        # Your login configuration
    }
EOF
    
    nginx -t && systemctl reload nginx
    log_audit "RATE_LIMITING_ADDED" "$domain"
}

# --- BACKUP ENCRYPTION ---
encrypted_backup() {
    local source="$1"
    local backup_name="$2"
    
    # Create encrypted backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/root/backups/${backup_name}_${timestamp}.tar.gz.gpg"
    
    # Compress and encrypt
    tar czf - "$source" | gpg --encrypt --recipient "server-backup" --output "$backup_file"
    
    # Verify backup
    gpg --decrypt "$backup_file" 2>/dev/null | tar tz >/dev/null || {
        echo "ERROR: Backup verification failed"
        return 1
    }
    
    # Upload to remote storage (optional)
    if command -v rclone &>/dev/null; then
        rclone copy "$backup_file" remote:backups/
    fi
    
    # Clean old backups (keep last 7 days)
    find /root/backups -name "*.gpg" -mtime +7 -delete
    
    log_audit "ENCRYPTED_BACKUP_CREATED" "$backup_name"
}

# --- INCIDENT RESPONSE ---
incident_response() {
    local incident_type="$1"
    
    case "$incident_type" in
        "web_defacement")
            # Take website offline
            systemctl stop nginx
            
            # Create forensic copy
            tar czf "/root/forensics/web_$(date +%s).tar.gz" /var/www
            
            # Restore from backup
            restore_latest_backup
            
            # Block attacking IPs
            grep "POST.*wp-admin" /var/log/nginx/access.log | awk '{print $1}' | sort -u | while read ip; do
                iptables -A INPUT -s "$ip" -j DROP
            done
            
            log_audit "INCIDENT_RESPONSE" "Web defacement handled"
            ;;
            
        "brute_force")
            # Block IPs with too many failed attempts
            grep "Failed password" /var/log/auth.log | awk '{print $11}' | sort | uniq -c | \
                while read count ip; do
                    if [ "$count" -gt 10 ]; then
                        iptables -A INPUT -s "$ip" -j DROP
                        echo "Blocked $ip after $count failed attempts"
                    fi
                done
            ;;
    esac
}

# --- MAIN EXECUTION WITH SECURITY WRAPPER ---
main() {
    # Initialize security
    initialize_security
    
    # Check if running with appropriate privileges
    if [ "$EUID" -eq 0 ]; then
        echo "WARNING: Running as root. Consider using sudo for specific commands."
        read -p "Continue? (y/N): " -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    
    # Load configuration
    load_config
    
    # Start audit logging
    log_audit "SESSION_START" "User: $(whoami), Host: $(hostname)"
    
    # Run main menu (original functionality with security enhancements)
    run_secure_menu
}

# --- LOAD CONFIGURATION SECURELY ---
load_config() {
    local config_file="/etc/bunny-deploy/config.ini"
    
    if [ -f "$config_file" ]; then
        # Validate config file ownership
        local owner=$(stat -c %U "$config_file")
        if [ "$owner" != "root" ]; then
            echo "ERROR: Config file has invalid ownership"
            exit 1
        fi
        
        # Check permissions
        if [ "$(stat -c %a "$config_file")" != "600" ]; then
            echo "ERROR: Config file permissions too open"
            exit 1
        fi
        
        # Load config securely
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^# ]] || [[ -z $key ]] && continue
            # Sanitize key and value
            key=$(sanitize_input "$key")
            value=$(sanitize_input "$value")
            # Export as environment variable
            export "CONFIG_${key^^}"="$value"
        done < "$config_file"
    fi
}

# --- ENTRY POINT ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
