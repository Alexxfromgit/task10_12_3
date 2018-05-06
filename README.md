# task10_12_3

Общие требования к выполнению практических заданий:

    1. Выполненное задание должно располагаться в отдельном репозитарии на github.com, т.е. если учетная запись на github называется ‘user’ и выполняется практическое задание с названием ‘task10_12_3’, то файлы задания должны быть доступны в репозитарии https://github.com/user/task10_12_3. 
    2. Для проверки выполнения ДЗ будет использована свежеустановленная VM из этого образа - https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
    3. Дополнительно в ВМ будут предустановлены пакеты qemu-kvm, libvirt-bin, virtinst, bridge-utils и genisoimage.
    4. Для выполнения ДЗ разрешается устанавливать любые дополнительные пакеты, помимо тех, что явно указаны в задании. В случае использования пакетов, которые не установлены в образе, необходимо предусмотреть их установку.
    5. Запуск скриптов во время проекта будет осуществляться от имени root
    6. Практические Задания по ЛК10-12 должны быть выполнены и загружены в соответствующие репозитарии до 23:59 13/05/18.

Задание  
Создание окружения
Используя возможности libvirt, virt-install и cloud-init необходимо осуществить автоматическое развертывание инфраструктуры из двух ВМ и ее конфигурацию согласно рис. 1 ниже.
    • Создание инфраструктуры - часть 1 задания task10_12
    • Развертывание контейнеров - часть 2 задания task10_12
    • Настройка NGINX в качестве reverse proxy с терминированием SSL/TLS - task6_7

<p align="center">
  <img src="https://image.ibb.co/iVORR7/lc10_12_3_jpg.png">
  
  # Рисунок 1 - Топология задания
  </p>

Используя XML шаблоны необходимо создать три libvirt-сети:

    • External - для подключения к Internet. Тип сети - NAT. Сеть должна иметь DHCP сервер и единственную статическую запись для  vm1
    • Internal - для связи между VM. Тип сети- Internal. Не имеет назначенных IP-адресов
    • Management - для удаленного управления ВМ. Тип сети - Internal. В отличие от предыдущей необходимо назначить IP адрес в настройках сети для того, чтобы обеспечить L3 связность между хостовой и виртуальными машинами. Сеть не должна иметь настроенный DHCP сервер.

Используя возможности пакета virt-install необходимо создать 2 виртуальные машины (vm1 и vm2) и корректно подключить их к созданным ранее сетям.

VM1 должна иметь 3 сетевых интерфейса:

    • External - для подключения к Internet.
    • Internal - для связи с VM2.
    • Management - для удаленного управления VM.
    
VM2 должна иметь 2 сетевых интерфейса:

    • Internal - для связи с VM1. 
    • Management - для удаленного управления VM.

Используя возможности cloud-init необходимо осуществить корректную начальную настройку виртуальных машин, а именно:

    • Установить имя хоста (vm1 или vm2)
    • Обеспечить возможность подключения к ВМ путем добавления заданного публичного SSH ключа
    • Корректно настроить сетевые интерфейсы
        ◦ На vm1:
            ▪ External интерфейс в режиме DHCP
            ▪ Internal интерфейс - статическая настройка
            ▪ Management интерфейс - статическая настройка
            ▪ Выполнить действия, необходимые для того, чтобы запросы к внешним ресурсам от vm2 корректно маршрутизировались через External интерфейс
        ◦ На vm2:
            ▪ Internal интерфейс - статическая настройка. Шлюз по умолчанию - IP адрес Internal интерфейса vm1. DNS сервер - 8.8.8.8
            ▪ Management интерфейс - статическая настройка
    • Создать и настроить vxlan туннель между виртуальными машинами
    • Установить пакет docker-ce из официального репозитория https://download.docker.com/linux/ubuntu
    • С помощью docker развернуть связку NGINX reverse proxy с терминированием TLS соединения для Apache, а именно:
        ◦ На vm1 должен быть настроен и запущен контейнер NGINX (из образа nginx:1.13), в который через docker volume примонтированы:
            ▪ Файл конфигурации nginx.conf
            ▪ Необходимые сертификаты (должны генерироваться в процессе установки)
            ▪ Локальная директория хоста для записи логов
        ◦ NGINX должен перенаправлять запросы на контейнер с apache2 (из образа httpd:2.4), развернутый на vm2, при чем:
            ▪ Трафик должен проходить через VxLAN туннель, настроенный между vm1 и vm2
            ▪ Порт, через который достижим контейнер с apache2, является конфигурируемым параметром
        ◦ На виртуальной машине vm2 запущен контейнер с apache2
    • Доступ ко внешним ресурсам из vm2 доступен исключительно через vm1

**Часть 1 - Необходимые файлы**

    1. В репозитории должен находиться файл с именем task10_12_3.sh. Именно он  является входной точкой и будет запущен
    2. В репозитории должен находиться файл с именем config. В нем должны содержаться конфигурируемые параметры, которые должен корректно прочитать и применить скрипт (имена виртуальных машин, имена интерфейсов, IP адреса и т.д.). Перечень конфигурируемых параметров приведен ниже.
    3. В репозитории могут находиться любые дополнительные файлы и папки на ваше усмотрение (например можно вынести функции в отдельный файл)
    4. В конечном результате после запуска скрипта необходимо обеспечить приведенную ниже иерархию файлов (допускается как генерация файлов скриптом, так и редактирование уже существующих в репозитории файлов; допускается наличие любых дополнительных файлов и директорий):

	WORKDIR				# script working directory
	├── config			# parameters file
	├── config-drives		# directory for config drives
	│   ├── vm1-config		# source files for vm1 cfg drive
	│   │   ├── meta-data	    	# meta-data file
	│   │   └── user-data	    	# user-data script
	│   └── vm2-config		# source files for vm2 cfg drive
	│       ├── meta-data	    	# meta-data file
	│       └── user-data	    	# user-data script
	├── docker			# directory with docker files
	│   ├── etc			# config directory
	│   │   └── nginx.conf	  	# NGINX configuration file
	│   └── certs			# directory with certificates
	│       ├── root.crt		# root CA certificate
	│       ├── web.crt		# NGINX certificate
	│       └── web.key		# NGINX private key
	├── task10_12_3.sh		# main script file
	└── networks			# directory for libvirt network XMLs
		├── external.xml	# external net XML definition
		├── internal.xml	# internal net XML definition
		└── management.xml	# management net XML definition

Пример файла **config**:

    # Libvirt networks
    # external network parameters
    EXTERNAL_NET_NAME=external
    EXTERNAL_NET_TYPE=dhcp
    EXTERNAL_NET=192.168.123
    EXTERNAL_NET_IP=${EXTERNAL_NET}.0
    EXTERNAL_NET_MASK=255.255.255.0
    EXTERNAL_NET_HOST_IP=${EXTERNAL_NET}.1
    VM1_EXTERNAL_IP=${EXTERNAL_NET}.101

    # internal network parameters
    INTERNAL_NET_NAME=internal
    INTERNAL_NET=192.168.124
    INTERNAL_NET_IP=${INTERNAL_NET}.0
    INTERNAL_NET_MASK=255.255.255.0

    # management network parameters
    MANAGEMENT_NET_NAME=management
    MANAGEMENT_NET=192.168.125
    MANAGEMENT_NET_IP=${MANAGEMENT_NET}.0
    MANAGEMENT_NET_MASK=255.255.255.0
    MANAGEMENT_HOST_IP=${MANAGEMENT_NET}.1

    # VMs global parameters
    SSH_PUB_KEY=/home/jenkins/.ssh/id_rsa.pub
    VM_TYPE=hvm
    VM_VIRT_TYPE=kvm
    VM_DNS=8.8.8.8
    VM_BASE_IMAGE=https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img

    # overlay
    VXLAN_NET=10.255.0
    VID=12345
    VXLAN_IF=vxlan0

    # VMs
    VM1_NAME=vm1
    VM1_NUM_CPU=1
    VM1_MB_RAM=512
    VM1_HDD=/var/lib/libvirt/images/vm1/vm1.qcow2
    VM1_CONFIG_ISO=/var/lib/libvirt/images/vm1/config-vm1.iso
    VM1_EXTERNAL_IF=ens3
    VM1_INTERNAL_IF=ens4
    VM1_MANAGEMENT_IF=ens5
    VM1_INTERNAL_IP=${INTERNAL_NET}.101
    VM1_MANAGEMENT_IP=${MANAGEMENT_NET}.101
    VM1_VXLAN_IP=${VXLAN_NET}.101

    VM2_NAME=vm2
    VM2_NUM_CPU=1
    VM2_MB_RAM=512
    VM2_HDD=/var/lib/libvirt/images/vm2/vm2.qcow2
    VM2_CONFIG_ISO=/var/lib/libvirt/images/vm2/config-vm2.iso
    VM2_INTERNAL_IF=ens3
    VM2_MANAGEMENT_IF=ens4
    VM2_INTERNAL_IP=${INTERNAL_NET}.102
    VM2_MANAGEMENT_IP=${MANAGEMENT_NET}.102
    VM2_VXLAN_IP=${VXLAN_NET}.102

    # Docker containers
    NGINX_IMAGE="nginx:1.13"
    APACHE_IMAGE="httpd:2.4"
    NGINX_PORT=17080
    APACHE_PORT=13254
    NGINX_LOG_DIR=/srv/log/nginx

**Часть 2 - Рекомендации**

Ниже приведены некоторые рекомендации, которые помогут вам корректно выполнить текущее задание:

    1. Для создания сетей в libvirt используйте XML файл с описанием сети и команды virsh net-define, virsh net-start
    2. Для создания виртуальных машин используйте virt-install
    3. Для настройки DHCP вам понадобится сгенерировать MAC адрес (или адреса). Можете воспользоваться этой командой:
	MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`
    4. Предусмотрите загрузку образа по адресу, указанному в файле config
    5. Для увеличения размера диска ВМ можно использовать команду qemu-img resize
    6. Для настройки имени хоста, SSH ключа и сетевых интерфейсов можно использовать meta-data файл.
    7. Для создания VxLAN туннеля, установки docker-ce, развертывания контейнеров используйте файл user-data. Некоторые статьи, которые помогут с настройкой VxLAN:
        a. Kernel.org doc
        b. IPv6 example
    8. Для создания ISO файла с конфигурационным диском можно воспользоваться утилитой mkisofs
    9. Используйте наработки из task6_7 и task10_12_2 для настройки связки apache2+nginx
    10. Использование compose файла для развертывания сервисов не обязательно

**Часть 3 - Проверка**

В ходе проверки будет копироваться репозиторий task10_12_3 и запускаться скрипт  task10_12_3.sh
Основна проверка будет заключаться в https запросе к vm1 на external_ip по порту, указанному в конфигурационном файле, и с указанием корневого сертификата (из директории docker/certs проекта, файл root.crt). Ожидается, что https соединение будет успешно установлено и в ответе будет страница apache2 по умолчанию (“It works!”).
Будет проверено наличие libvirt сетей, виртуальных машин и корректность подключения виртуальных машин к сетям.
Для проверки будет использоваться SSH соединение с виртуальными машинами через Management сеть. Для подключения будет использоваться логин ubuntu и публичный SSH ключ, указанный в файле config

Автоматически будет проверена конфигурация сетевых интерфейсов:

    • назначены правильные IP адреса
    • обе машины имеют доступ во внешнюю сеть
    • VXLAN туннель настроен между двумя ВМ
    
Будет проверено наличие пакета docker-ce
Будет проверено наличие контейнеров nginx (на vm1) и apache (на vm2), а также их базовые образы (nginx:1.13 и httpd:2.4 соответственно).
Также будет проверена конфигурация точек монтирования для контейнера nginx (конфигурационный файл, сертификаты, логи). Будет проверено наличие записей в /srv/logs/nginx/access.log на докер хосте.
После запуска скрипта будет проверено наличие обязательных файлов и директорий в директории проекта (XML-файлы, директории для создания конфигурационных дисков, docker/etc/nginx.conf, docker/certs/)


