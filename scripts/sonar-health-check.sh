#!/bin/bash

# SonarQube Health Check Script
# هذا السكريبت يتحقق من صحة SonarQube وPostgreSQL

set -e

# الألوان للطباعة
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# الدوال المساعدة
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# متغيرات
SONARQUBE_URL="http://localhost:9000"
SONARQUBE_API_URL="${SONARQUBE_URL}/api"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_USER="sonaruser"
POSTGRES_DB="sonarqube"

# التحقق من Docker والحاويات
check_docker_containers() {
    log_info "التحقق من Docker containers..."
    
    # التحقق من container SonarQube
    if docker ps | grep -q "sonarqube"; then
        log_success "SonarQube container يعمل"
        SONARQUBE_RUNNING=true
    else
        log_error "SonarQube container لا يعمل"
        SONARQUBE_RUNNING=false
    fi
    
    # التحقق من container PostgreSQL
    if docker ps | grep -q "sonarqube-postgres"; then
        log_success "PostgreSQL container يعمل"
        POSTGRES_RUNNING=true
    else
        log_error "PostgreSQL container لا يعمل"
        POSTGRES_RUNNING=false
    fi
}

# التحقق من SonarQube API
check_sonarqube_api() {
    log_info "التحقق من SonarQube API..."
    
    if [ "$SONARQUBE_RUNNING" = true ]; then
        # التحقق من health endpoint
        if curl -s "${SONARQUBE_API_URL}/system/health" > /dev/null; then
            log_success "SonarQube API متاح"
            
            # الحصول على حالة النظام
            HEALTH_STATUS=$(curl -s "${SONARQUBE_API_URL}/system/health" | grep -o '"health":"[^"]*"' | cut -d'"' -f4)
            
            case $HEALTH_STATUS in
                "GREEN")
                    log_success "حالة النظام: GREEN (جيد)"
                    ;;
                "YELLOW")
                    log_warning "حالة النظام: YELLOW (تحذير)"
                    ;;
                "RED")
                    log_error "حالة النظام: RED (خطأ)"
                    ;;
                *)
                    log_warning "حالة النظام غير معروفة"
                    ;;
            esac
            
            # التحقق من إصدار SonarQube
            VERSION=$(curl -s "${SONARQUBE_API_URL}/system/status" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
            log_info "إصدار SonarQube: ${VERSION:-غير معروف}"
            
            # التحقق من plugins
            PLUGINS=$(curl -s "${SONARQUBE_API_URL}/system/plugins/installed" | grep -o '"name":"[^"]*"' | wc -l)
            log_info "عدد Plugins المثبتة: $PLUGINS"
            
        else
            log_error "SonarQube API غير متاح"
        fi
    else
        log_error "لا يمكن التحقق من SonarQube API - Container لا يعمل"
    fi
}

# التحقق من PostgreSQL
check_postgresql() {
    log_info "التحقق من PostgreSQL..."
    
    if [ "$POSTGRES_RUNNING" = true ]; then
        # التحقق من الاتصال بقاعدة البيانات
        if docker exec sonarqube-postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
            log_success "PostgreSQL متصل ويعمل"
            
            # التحقق من حجم قاعدة البيانات
            DB_SIZE=$(docker exec sonarqube-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));" 2>/dev/null | xargs)
            log_info "حجم قاعدة البيانات: ${DB_SIZE:-غير معروف}"
            
            # التحقق من عدد الجداول
            TABLE_COUNT=$(docker exec sonarqube-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)
            log_info "عدد الجداول: ${TABLE_COUNT:-غير معروف}"
            
        else
            log_error "PostgreSQL لا يقبل الاتصالات"
        fi
    else
        log_error "لا يمكن التحقق من PostgreSQL - Container لا يعمل"
    fi
}

# التحقق من المساحة المستخدمة
check_disk_usage() {
    log_info "التحقق من استخدام القرص..."
    
    # التحقق من مجلد البيانات
    if [ -d "data/sonarqube" ]; then
        DATA_SIZE=$(du -sh data/sonarqube 2>/dev/null | cut -f1)
        log_info "حجم بيانات SonarQube: ${DATA_SIZE:-غير معروف}"
    fi
    
    # التحقق من مجلد Logs
    if [ -d "logs/sonarqube" ]; then
        LOGS_SIZE=$(du -sh logs/sonarqube 2>/dev/null | cut -f1)
        log_info "حجم سجلات SonarQube: ${LOGS_SIZE:-غير معروف}"
    fi
    
    # التحقق من Docker volumes
    log_info "حجم Docker volumes:"
    docker volume ls | grep sonarqube | while read line; do
        VOLUME_NAME=$(echo $line | awk '{print $2}')
        VOLUME_SIZE=$(docker volume inspect "$VOLUME_NAME" --format '{{ .Mountpoint }}' | xargs du -sh 2>/dev/null | cut -f1)
        echo "  - $VOLUME_NAME: ${VOLUME_SIZE:-غير معروف}"
    done
}

# التحقق من الشبكة
check_network() {
    log_info "التحقق من الشبكة..."
    
    # التحقق من Docker network
    if docker network ls | grep -q "sonarqube-network"; then
        log_success "Docker network 'sonarqube-network' موجود"
    else
        log_error "Docker network 'sonarqube-network' غير موجود"
    fi
    
    # التحقق من المنافذ المفتوحة
    if netstat -ln | grep -q ":9000"; then
        log_success "Port 9000 مفتوح (SonarQube)"
    else
        log_warning "Port 9000 غير مفتوح"
    fi
    
    if netstat -ln | grep -q ":5432"; then
        log_success "Port 5432 مفتوح (PostgreSQL)"
    else
        log_warning "Port 5432 غير مفتوح"
    fi
}

# عرض سجلات الأخطاء
check_recent_logs() {
    log_info "التحقق من السجلات الحديثة..."
    
    echo "=== سجلات SonarQube (آخر 10 أسطر) ==="
    docker-compose -f docker-compose.sonar.yml logs --tail=10 sonarqube 2>/dev/null || log_error "لا يمكن قراءة سجلات SonarQube"
    
    echo
    echo "=== سجلات PostgreSQL (آخر 5 أسطر) ==="
    docker-compose -f docker-compose.sonar.yml logs --tail=5 sonarqube-postgres 2>/dev/null || log_error "لا يمكن قراءة سجلات PostgreSQL"
}

# تقرير نهائي
generate_report() {
    echo
    echo "=== تقرير الصحة النهائي ==="
    
    if [ "$SONARQUBE_RUNNING" = true ] && [ "$POSTGRES_RUNNING" = true ]; then
        log_success "SonarQube يعمل بشكل طبيعي"
        return 0
    else
        log_error "هناك مشاكل في SonarQube"
        return 1
    fi
}

# دالة رئيسية
main() {
    echo "=== SonarQube Health Check ==="
    echo "بدء فحص صحة SonarQube..."
    echo
    
    check_docker_containers
    echo
    
    check_sonarqube_api
    echo
    
    check_postgresql
    echo
    
    check_disk_usage
    echo
    
    check_network
    echo
    
    check_recent_logs
    echo
    
    generate_report
}

# تشغيل السكريبت الرئيسي
main "$@"
