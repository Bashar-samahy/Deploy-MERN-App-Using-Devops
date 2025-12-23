#!/bin/bash

# SonarQube Setup Script
# هذا السكريبت يقوم بإعداد SonarQube بالكامل

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

# التحقق من المتطلبات
check_requirements() {
    log_info "التحقق من المتطلبات..."
    
    # التحقق من Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker غير مثبت"
        exit 1
    fi
    
    # التحقق من Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose غير مثبت"
        exit 1
    fi
    
    # التحقق من systemd
    if ! command -v systemctl &> /dev/null; then
        log_warning "systemd غير متوفر - سيتم تشغيل SonarQube يدوياً"
        SYSTEMD_AVAILABLE=false
    else
        SYSTEMD_AVAILABLE=true
    fi
    
    log_success "جميع المتطلبات متوفرة"
}

# إنشاء ملف البيئة
setup_environment() {
    log_info "إعداد ملف البيئة..."
    
    if [ ! -f .env ]; then
        cat > .env << EOF
# SonarQube Environment Variables
SONAR_TOKEN=
SONAR_HOST_URL=http://localhost:9000
SONAR_PROJECT_KEY=mern-app-devops

# Database Configuration
POSTGRES_USER=sonaruser
POSTGRES_PASSWORD=sonarpass
POSTGRES_DB=sonarqube

# Network Configuration
SONARQUBE_PORT=9000
POSTGRES_PORT=5432
EOF
        log_success "تم إنشاء ملف .env"
    else
        log_warning "ملف .env موجود مسبقاً"
    fi
}

# إعداد المجلدات والصلاحيات
setup_directories() {
    log_info "إعداد المجلدات..."
    
    # إنشاء المجلدات المطلوبة
    mkdir -p data/sonarqube logs/sonarqube config/sonarqube
    
    # تعيين صلاحيات صحيحة
    sudo chown -R 1000:1000 data/sonarqube logs/sonarqube
    sudo chmod -R 755 data/sonarqube logs/sonarqube
    
    log_success "تم إعداد المجلدات"
}

# تشغيل SonarQube
start_sonarqube() {
    log_info "تشغيل SonarQube..."
    
    # إيقاف أي مثيلات سابقة
    docker-compose -f docker-compose.sonar.yml down 2>/dev/null || true
    
    # تشغيل SonarQube
    docker-compose -f docker-compose.sonar.yml up -d
    
    log_success "تم تشغيل SonarQube"
}

# التحقق من حالة SonarQube
check_status() {
    log_info "التحقق من حالة SonarQube..."
    
    # انتظار بدء التشغيل
    sleep 10
    
    # التحقق من حالة الحاويات
    docker-compose -f docker-compose.sonar.yml ps
    
    # اختبار الاتصال
    if curl -s http://localhost:9000/api/system/health | grep -q "GREEN"; then
        log_success "SonarQube يعمل بشكل صحيح"
    else
        log_warning "SonarQube قد لا يكون جاهزاً بعد - انتظر قليلاً"
    fi
}

# إعداد Systemd Service
setup_systemd() {
    if [ "$SYSTEMD_AVAILABLE" = true ]; then
        log_info "إعداد Systemd Service..."
        
        # نسخ ملف الخدمة
        sudo cp systemd/sonarqube.service /etc/systemd/system/
        
        # إعادة تحميل systemd
        sudo systemctl daemon-reload
        
        # تفعيل الخدمة
        sudo systemctl enable sonarqube
        
        log_success "تم إعداد Systemd Service"
    fi
}

# طباعة معلومات الاستخدام
print_usage_info() {
    echo
    echo "=== معلومات الاستخدام ==="
    echo "رابط SonarQube: http://localhost:9000"
    echo "اسم المستخدم: admin"
    echo "كلمة المرور: admin (يجب تغييرها)"
    echo
    echo "=== الأوامر المفيدة ==="
    echo "لإيقاف SonarQube:    docker-compose -f docker-compose.sonar.yml down"
    echo "لإعادة تشغيل:        docker-compose -f docker-compose.sonar.yml restart"
    echo "لعرض السجلات:        docker-compose -f docker-compose.sonar.yml logs -f"
    echo "لمراقبة الحالة:      docker-compose -f docker-compose.sonar.yml ps"
    echo
    if [ "$SYSTEMD_AVAILABLE" = true ]; then
        echo "=== Systemd Commands ==="
        echo "لبدء الخدمة:        sudo systemctl start sonarqube"
        echo "لإيقاف الخدمة:      sudo systemctl stop sonarqube"
        echo "لمراجعة الحالة:     sudo systemctl status sonarqube"
    fi
    echo
}

# دالة رئيسية
main() {
    echo "=== SonarQube Setup Script ==="
    echo "بدء إعداد SonarQube..."
    
    check_requirements
    setup_environment
    setup_directories
    start_sonarqube
    check_status
    setup_systemd
    print_usage_info
    
    log_success "تم إعداد SonarQube بنجاح!"
}

# تشغيل السكريبت الرئيسي
main "$@"
