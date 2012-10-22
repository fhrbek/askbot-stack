# Set up the postgres DB for askbot, very basic at present.
#
class askbot::postgres {

  include askbot::params
  include 'postgresql'
  include 'postgresql::server'

  $askbot_db_name = $askbot::params::askbot_db_name
  $askbot_db_user = $askbot::params::askbot_db_user
  $askbot_db_pass = $askbot::params::askbot_db_pass


  postgresql::database { $askbot_db_name: }

  postgresql::database_user { 'askbot':
    password_hash => $askbot_db_pass,
  }

  postgresql::database_grant{ 'grant_askbot':
    privilege => 'OWNER',
    db        => $askbot_db_name,
    role      => $askbot_db_user,
    require   => [ Postgresql::Database[$askbot_db_name],
                    Postgresql::Database_user[$askbot_db_user], ],
  }

  postgresql::database_grant{ 'connect_askbot':
    privilege => 'CONNECT',
    db        => $askbot_db_name,
    role      => $askbot_db_user,
    require   => [ Postgresql::Database[$askbot_db_name],
                    Postgresql::Database_user[$askbot_db_user], ],
  }

}

