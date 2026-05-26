#!/bin/bash

usage() {
    cat <<EOF
使用方法: 
  API Token方式:  $0 -k <API_TOKEN> -d <DOMAIN> -s <SUBDOMAIN> -t <RECORD_TYPE>
  Global Key方式: $0 -e <EMAIL> -g <GLOBAL_KEY> -d <DOMAIN> -s <SUBDOMAIN> -t <RECORD_TYPE>

参数说明:
  -k    Cloudflare API Token（推荐）
  -e    Cloudflare 账户邮箱（使用Global Key时必填）
  -g    Cloudflare Global API Key（使用Global Key时必填）
  -d    主域名，如 example.com（必填）
  -s    子域名，如 www 或 @（必填）
  -t    DNS记录类型，A 或 AAAA（必填）

示例:
  $0 -k "v1.0-xxxx" -d "example.com" -s "home" -t "A"
  $0 -e "user@example.com" -g "9775cd3e..." -d "example.com" -s "home" -t "A"
EOF
    exit 1
}

# 解析参数
while getopts "k:e:g:d:s:t:h" opt; do
    case $opt in
        k) CF_API_TOKEN="$OPTARG" ;;
        e) CF_EMAIL="$OPTARG" ;;
        g) CF_GLOBAL_KEY="$OPTARG" ;;
        d) DOMAIN="$OPTARG" ;;
        s) SUBDOMAIN="$OPTARG" ;;
        t) RECORD_TYPE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# 检查认证方式
if [ -n "$CF_API_TOKEN" ]; then
    AUTH_TYPE="token"
elif [ -n "$CF_EMAIL" ] && [ -n "$CF_GLOBAL_KEY" ]; then
    AUTH_TYPE="global"
else
    echo "错误: 必须提供 -k (API Token) 或 -e + -g (邮箱+Global Key)"
    usage
fi

[ -z "$DOMAIN" ] && echo "错误: -d DOMAIN 不能为空" && usage
[ -z "$SUBDOMAIN" ] && echo "错误: -s SUBDOMAIN 不能为空" && usage
[ -z "$RECORD_TYPE" ] && echo "错误: -t RECORD_TYPE 不能为空" && usage

case "$RECORD_TYPE" in
    A|AAAA) ;;
    *) echo "错误: RECORD_TYPE 必须为 A 或 AAAA" && exit 1 ;;
esac

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1，尝试安装..."
        install_pkg "$1" || exit 1
    }
}

install_pkg() {
    if [ -f /etc/debian_version ]; then
        apt update -qq && apt install -y -qq "$1"
    elif [ -f /etc/redhat-release ]; then
        yum install -y "$1"
    elif command -v opkg >/dev/null 2>&1; then
        opkg update && opkg install "$1"
    else
        return 1
    fi
}

get_dns_ip() {
    local name="$1"
    local type="$2"
    
    echo "正在查询DNS记录: $name ($type)" >&2
    
    if command -v dig >/dev/null 2>&1; then
        local ip=$(dig +short "$name" "$type" | head -1)
        if [[ "$ip" =~ ^[0-9a-fA-F\.:]+$ ]]; then
            echo "通过dig获取到DNS IP: $ip" >&2
            echo "$ip"
            return
        fi
    fi
    
    if command -v nslookup >/dev/null 2>&1; then
        local ip
        if [ "$type" = "A" ]; then
            ip=$(nslookup "$name" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        else
            ip=$(nslookup -type=AAAA "$name" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        fi
        if [[ "$ip" =~ ^[0-9a-fA-F\.:]+$ ]]; then
            echo "通过nslookup获取到DNS IP: $ip" >&2
            echo "$ip"
            return
        fi
    fi
    
    echo "DNS查询失败，记录可能不存在" >&2
    echo ""
}

get_public_ip() {
    local type="$1"
    local apis=()
    
    if [ "$type" = "A" ]; then
        apis=(
            "https://v4.ipgg.cn/ip"
            "https://api.ipify.org"
            "https://ipv4.icanhazip.com"
            "https://ifconfig.me/ip"
        )
    else
        apis=(
            "https://v6.ipgg.cn/ip"
            "https://api6.ipify.org"
            "https://ipv6.icanhazip.com"
            "https://ifconfig.me/ip"
        )
    fi
    
    for api in "${apis[@]}"; do
        echo "尝试从 $api 获取IP..." >&2
        local ip=$(curl -s --max-time 10 "$api" | tr -d '[:space:]')
        
        if [[ "$ip" =~ ^[0-9a-fA-F\.:]+$ ]]; then
            echo "成功获取IP: $ip" >&2
            echo "$ip"
            return 0
        fi
    done
    
    return 1
}

# 执行Cloudflare API请求的函数
cf_api_call() {
    local method="$1"
    local url="$2"
    local data="$3"
    
    if [ "$AUTH_TYPE" = "token" ]; then
        if [ -n "$data" ]; then
            curl -s -X "$method" "$url" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data "$data"
        else
            curl -s -X "$method" "$url" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json"
        fi
    else
        if [ -n "$data" ]; then
            curl -s -X "$method" "$url" \
                -H "X-Auth-Email: $CF_EMAIL" \
                -H "X-Auth-Key: $CF_GLOBAL_KEY" \
                -H "Content-Type: application/json" \
                --data "$data"
        else
            curl -s -X "$method" "$url" \
                -H "X-Auth-Email: $CF_EMAIL" \
                -H "X-Auth-Key: $CF_GLOBAL_KEY" \
                -H "Content-Type: application/json"
        fi
    fi
}

need_cmd curl
need_cmd jq

case "$RECORD_TYPE" in
    A) DNS_TYPE="A" ;;
    AAAA) DNS_TYPE="AAAA" ;;
esac

echo "正在获取当前出口IP..."
CURRENT_IP=$(get_public_ip "$RECORD_TYPE")
if [ $? -ne 0 ] || [ -z "$CURRENT_IP" ]; then
    echo "获取出口 IP 失败，请检查网络连接"
    exit 1
fi
echo "当前出口IP: $CURRENT_IP"

if [ "$SUBDOMAIN" = "@" ]; then
    record_name="$DOMAIN"
else
    record_name="$SUBDOMAIN.$DOMAIN"
fi

DNS_IP=$(get_dns_ip "$record_name" "$DNS_TYPE")

if [ -n "$DNS_IP" ]; then
    if [ "$CURRENT_IP" == "$DNS_IP" ]; then
        echo "出口 IP 与 DNS 一致，无需更新 ($CURRENT_IP)"
        exit 0
    else
        echo "IP不一致，需要更新: DNS=$DNS_IP, 当前=$CURRENT_IP"
    fi
else
    echo "DNS记录不存在或查询失败，将创建新记录"
fi

echo "正在获取Cloudflare Zone ID..."
zone_json=$(cf_api_call "GET" "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN")

# 检查API响应
success=$(echo "$zone_json" | jq -r '.success')
if [ "$success" != "true" ]; then
    echo "Cloudflare API 返回错误:"
    echo "$zone_json" | jq -r '.errors[]?.message'
    exit 1
fi

result_count=$(echo "$zone_json" | jq -r '.result | length')
if [ "$result_count" -eq 0 ]; then
    echo "未找到域名 $DOMAIN"
    echo "请检查: 1)域名已添加到Cloudflare 2)API权限正确"
    exit 1
fi

ZONE_ID=$(echo "$zone_json" | jq -r '.result[0].id')
[ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ] && echo "无法获取 Zone ID" && exit 1
echo "Zone ID: $ZONE_ID"

echo "正在查询现有DNS记录..."
record_json=$(cf_api_call "GET" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record_name&type=$RECORD_TYPE")
RECORD_ID=$(echo "$record_json" | jq -r '.result[0].id')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    echo "记录不存在，创建中..."
    response=$(cf_api_call "POST" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        "{\"type\":\"$RECORD_TYPE\",\"name\":\"$record_name\",\"content\":\"$CURRENT_IP\",\"ttl\":600,\"proxied\":false}")
else
    echo "记录存在，Record ID: $RECORD_ID，更新中..."
    response=$(cf_api_call "PUT" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        "{\"type\":\"$RECORD_TYPE\",\"name\":\"$record_name\",\"content\":\"$CURRENT_IP\",\"ttl\":600,\"proxied\":false}")
fi

echo "$response" | grep -q '"success":true' && echo "更新成功: $record_name -> $CURRENT_IP" || {
    echo "更新失败"
    echo "$response"
    exit 1
}
