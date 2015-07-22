# == Class percona::params
#
# === Parameters:
#
# === Provided parameters:
#
# === Examples:
#
# ==== Setting global and default configuration options.
#
# === Todo:
#
# TODO: Document parameters
#
class percona::cluster {
  if ( $percona::cluster ) {
    $tmp_params = {
      'mysqld/server_id'                => $percona::cluster_index,
      'mysqld/wsrep_cluster_address'    => $percona::cluster_address,
      'mysqld/wsrep_node_name'          => $percona::cluster_node_name,
      'mysqld/wsrep_cluster_name'       => $percona::cluster_name,
      'mysqld/wsrep_slave_threads'      => $percona::cluster_slave_threads,
      'mysqld/wsrep_sst_method'         => $percona::cluster_sst_method,
      'mysqld/wsrep_provider'           => $percona::cluster_wsrep_provider,
      'mysqld/wsrep_sst_auth'           => "${percona::cluster_replication_user}:${percona::cluster_replication_password}",
      'mysqld/innodb_autoinc_lock_mode' => '2',
    }


   if $percona::cluster_node_address {
     $tmp_params2 = $tmp_params + { 'mysqld/wsrep_node_address' => $percona::cluster_node_address }
   } else {
     $tmp_params2 = $tmp_params
   }

   if $percona::cluster_notify_cmd {
     $params = $tmp_params2 + { 'mysqld/wsrep_notify_cmd' => $percona::cluster_notify_cmd }
   } else {
     $params = $tmp_params2
   }
  }

  # For checking the cluster's health
#  if $::percona::cluster {
#    file { '/etc/xinetd.d/mysqlchk':
#      source => "puppet:///modules/percona/xinetd.d/mysqlchk",
#      owner  => 'root',
#      group  => 'root',
#      mode   => '0555',
#    }
#  }
}
