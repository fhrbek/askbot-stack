# Forked from https://github.com/stahnma/puppet-module-askbot/
#
class askbot (
  $vhost            = $fqdn,
  $prereqs          = $askbot::params::prereqs,
  $web_user         = $askbot::params::web_user,
  $web_group        = $askbot::params::web_group,
  $askbot_provider  = $askbot::params::askbot_provider,
  $askbot_home      = $askbot::params::askbot_home,
  $backup_db        = true,
) inherits askbot::params {

  include askbot::postgres
  include askbot::opinions

  motd::register{ "askbot Q&A site at ${vhost}": }

  # Resource Defaults
  Exec {
    path      => [ '/bin', '/usr/bin', '/sbin', '/usr/sbin' ],
    logoutput => on_failure,
  }

  package { $prereqs:
    ensure => installed,
  }

  # Due to
  # https://bitbucket.org/bkroeze/django-livesettings/issue/32/impossible-to-easy-use-livesettings
  # Which states 'Impossible to easy use livesettings without memcached'
  # we should probably use memcached.
  package {
    'memcached':
      ensure => present;
    'python-memcache':
      ensure => present;
  }

  service { 'memcached':
    ensure    => running,
    enable    => true,
    hasstatus => true,
    require   => Package['memcached'],
  }

  package { 'askbot':
    ensure   => installed,
    provider => $askbot_provider,
    require  => Package[$prereqs],
  }

  file { '/var/log/askbot':
    ensure  => directory,
    owner   => $web_user,
    group   => $web_group,
    require => Package['askbot'],
  }

  file { '/var/log/askbot/askbot.log':
    owner   => $web_user,
    group   => $web_group,
    mode    => '0644',
    require => Package['askbot'],
  }

  # Allow users to upload files
  # This should be secured in some maner probably
  file { 'upfiles':
    ensure  => directory,
    path    => "${askbot_home}/upfiles",
    owner   => 0,
    group   => $web_group,
    mode    => '2770',
    require => Package['askbot'],
  }

  exec { 'askbot_syncdb':
    cwd     => '/etc/askbot/sites/ask/config/',
    command => 'python manage.py syncdb --noinput',
    require => [  File['upfiles'], Class['askbot::postgres'], ],
  }

  exec { 'askbot_migrate_db':
    cwd       => '/etc/askbot/sites/ask/config/',
    command   => 'python manage.py migrate askbot',
    require   => [ Exec['askbot_syncdb'] ],
  }

  # Create a directory structure in /etc for sanity
  file { '/etc/askbot':                   ensure => directory, } ->
  file { '/etc/askbot/sites':             ensure => directory, } ->
  file { '/etc/askbot/sites/ask':         ensure => directory, } ->
  file { '/etc/askbot/sites/ask/config':  ensure => directory, }

  file { '/etc/askbot/sites/ask/config/__init__.py':
    ensure => present,
    source => 'puppet:///modules/askbot/setup_templates/__init__.py',
    owner  => 0,
    group  => 0,
  }

  file { '/etc/askbot/sites/ask/config/urls.py':
    ensure => present,
    source => 'puppet:///modules/askbot/setup_templates/urls.py',
    owner  => 0,
    group  => 0,
  }

  file { '/etc/askbot/sites/ask/config/manage.py':
    ensure => present,
    source => 'puppet:///modules/askbot/setup_templates/manage.py',
    owner  => 0,
    group  => 0,
  }

  file { '/usr/sbin/askbot.wsgi':
    ensure => present,
    owner  => 0,
    group  => 0,
    mode   => '0755',
    source => 'puppet:///modules/askbot/askbot.wsgi',
  }

  exec { 'askbot_build_assets':
    cwd     => '/etc/askbot/sites/ask/config/',
    command => 'yes yes | python manage.py collectstatic',
    require => [ Exec['askbot_syncdb'], Exec['askbot_migrate_db'] ],
  }

  exec { 'askbot_add_auth':
    cwd     => '/etc/askbot/sites/ask/config/',
    command => 'python manage.py migrate django_authopenid',
    require => [ Exec['askbot_migrate_db'] ],
  }

  file { '/etc/askbot/sites/ask/config/settings.py':
    ensure  => present,
    content => template('askbot/settings.erb'),
    owner   => $web_user,
    group   => $web_group,
    mode    => '0640',
    require => File['/etc/askbot/sites/ask/config'],
  }

  $django_path = "${askbot::params::py_location}/django"

  # Some "hotfixes" I applied, as root.
  file{ "${askbot_home}/skins/admin":
    ensure => directory,
  }
  file{ "${askbot_home}/skins/admin/css":
    ensure  => directory,
    require => File["${askbot_home}/skins/admin"],
  }

  # Is this quite ugly, or very ugly?
  file{
    "${askbot_home}/skins/admin/css/base.css":
      ensure  => link,
      target  => "${django_path}/contrib/admin/media/css/base.css",
      require => File["${askbot_home}/skins/admin/css"];
    "${askbot_home}/skins/admin/css/dashboard.css":
      ensure  => link,
      target  => "${django_path}/contrib/admin/media/css/dashboard.css",
      require => File["${askbot_home}/skins/admin/css"];
    "${askbot_home}/skins/admin/css/forms.css":
      ensure  => link,
      target  => "${django_path}/contrib/admin/media/css/forms.css",
      require => File["${askbot_home}/skins/admin/css"];
    "${askbot_home}/skins/admin/css/widgets.css":
      ensure  => link,
      target  => "${django_path}/contrib/admin/media/css/widgets.css",
      require => File["${askbot_home}/skins/admin/css"],
  }

  file {
    '/etc/askbot/sites/ask/config/askbot/':
      ensure => directory;
    '/etc/askbot/sites/ask/config/askbot/upfiles':
      target  => '/usr/local/lib/python2.7/dist-packages/askbot/upfiles/ask',
      require => File['/etc/askbot/sites/ask/config/askbot/'];
  }

  # needed for ssl?
  include apache::ssl

  apache::vhost{ "${vhost}_ssl":
    servername => $vhost,
    docroot    => $askbot::params::askbot_home,
    ssl        => true,
    port       => 443,
    priority   => 70,
    template   => 'askbot/webserver_config.erb',
    subscribe  => File['/etc/askbot/sites/ask/config/settings.py'],
  }

  apache::vhost::httptohttps{ $vhost:
    priority   => 90,
    require    => Apache::Vhost["${vhost}_ssl"],
  }

  # Compress the pages in askbot, as we can.
  a2mod{ 'deflate':
    ensure => present,
    before => Apache::Vhost["${vhost}_ssl"],
  }

  # We're using expires, so we need to say we want it here.
  # It's virtualised in ::apache
  realize(A2mod['expires'])


  # We may need to use wsgi, hopefully this doesn't clash with it
  # somewhere else, but it means this module doesn't rely on as many
  # things.
  package{ $askbot::params::wsgi:
    ensure => present,
  }

  a2mod { 'wsgi':
    ensure  => present,
    before  => Apache::Vhost["${vhost}_ssl"],
    require => Package[$askbot::params::wsgi],
  }


  # Backup using our bacula-fu, if we want to.
  if $backup_db == true {
    bacula::postgres{ $askbot::params::askbot_db_name: }
  }
}
