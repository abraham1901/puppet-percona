Puppet::Type.type(:mysql_grant).provide(:mysql) do

  desc "Uses mysql as database."

  defaultfor :kernel => 'Linux'

  optional_commands :mysql      => 'mysql'
  optional_commands :mysqladmin => 'mysqladmin'

  def mysql_args(*args)
    if @resource and @resource[:mgmt_cnf].is_a?(String)
      args.insert(0, "--defaults-file=#{@resource[:mgmt_cnf]}")
    end
    args
  end

  def user_privs
    unless defined? @@user_privs
      @@user_privs = query_user_privs
    end
    @@user_privs
  end

  def db_privs
    unless defined? @@db_privs
      @@db_privs = query_db_privs
    end
    @@db_privs
  end

  def query_user_privs
    results = mysql(mysql_args("mysql", "-Be", "describe user"))
    column_names = results.split(/\n/).map { |l| l.chomp.split(/\t/)[0] }
    @user_privs = column_names.delete_if { |e| !( e =~/_priv$/) }
    @user_privs
  end

  def query_db_privs
    results = mysql(mysql_args("mysql", "-Be", "describe db"))
    column_names = results.split(/\n/).map { |l| l.chomp.split(/\t/)[0] }
    @db_privs = column_names.delete_if { |e| !(e =~/_priv$/) }
    @db_privs
  end

  def mysql_flush
    mysqladmin(mysql_args("flush-privileges"))
  end

  # this parses the
  def split_name(string)
    matches = /^([^@]*)@([^\/]*)(\/(.*))?$/.match(string).captures.compact
    case matches.length
    when 2
      {
        :type => :user,
        :user => matches[0],
        :host => matches[1]
      }
    when 4
      {
        :type => :db,
        :user => matches[0],
        :host => matches[1],
        :db => matches[3]
      }
    end
  end

  def create_row
    unless @resource.should(:privileges).empty?
      name = split_name(@resource[:name])
      case name[:type]
      when :user
        mysql(mysql_args("mysql", "-e", "INSERT INTO user (host, user) VALUES ('%s', '%s')" % [
          name[:host], name[:user],
        ]))
      when :db
        mysql(mysql_args("mysql", "-e", "INSERT INTO db (host, user, db) VALUES ('%s', '%s', '%s')" % [
          name[:host], name[:user], name[:db],
        ]))
      end
      mysql_flush
    end
  end

  def destroy
    mysql(mysql_args("mysql", "-e", "REVOKE ALL ON '%s'.* FROM '%s@%s'" % [
      @resource[:privileges], @resource[:database], @resource[:name], @resource[:host]
    ]))
  end

  def row_exists?
    name = split_name(@resource[:name])
    fields = [:user, :host]
    if name[:type] == :db
      fields << :db
    end
    not mysql(mysql_args("mysql", "-NBe", 'SELECT "1" FROM %s WHERE %s' % [ name[:type], fields.map do |f| "%s=\"%s\"" % [f, name[f]] end.join(' AND ')])).empty?
  end

  def all_privs_set?
    all_privs = case split_name(@resource[:name])[:type]
                when :user
                  user_privs
                when :db
                  db_privs
                end
    all_privs = all_privs.collect do |p| p.downcase end.sort.join("|")
    privs = privileges.collect do |p| p.downcase end.sort.join("|")

    all_privs == privs
  end

  def privileges
    name = split_name(@resource[:name])
    privs = ""

    case name[:type]
    when :user
      privs = mysql(mysql_args("mysql", "-Be", 'select * from user where user="%s" and host="%s"' % [ name[:user], name[:host] ]))
    when :db
      privs = mysql(mysql_args("mysql", "-Be", 'select * from db where user="%s" and host="%s" and db="%s"' % [ name[:user], name[:host], name[:db] ]))
    end

    if privs.match(/^$/)
      privs = [] # no result, no privs
    else
      # returns a line with field names and a line with values, each tab-separated
      privs = privs.split(/\n/).map! do |l| l.chomp.split(/\t/) end
      # transpose the lines, so we have key/value pairs
      privs = privs[0].zip(privs[1])
      privs = privs.select do |p| p[0].match(/_priv$/) and p[1] == 'Y' end
    end

    privs.collect do |p| p[0] end
  end

  def privileges=(privs)
    unless row_exists?
      create_row
    end

    # puts "Setting privs: ", privs.join(", ")
    name = split_name(@resource[:name])
    stmt = ''
    where = ''
    all_privs = []
    case name[:type]
    when :user
      stmt = 'update user set '
      where = ' where user="%s" and host="%s"' % [ name[:user], name[:host] ]
      all_privs = user_privs
    when :db
      stmt = 'update db set '
      where = ' where user="%s" and host="%s" and db="%s"' % [ name[:user], name[:host], name[:db] ]
      all_privs = db_privs
    end

    if privs[0].downcase == 'all'
      privs = all_privs
    end

    # Downcase the requested priviliges for case-insensitive selection
    # we don't map! here because the all_privs object has to remain in
    # the same case the DB gave it to us in
    privs = privs.map { |p| p.downcase }

    set = all_privs.collect do |p| "%s = '%s'" % [p, privs.include?(p.downcase) ? 'Y' : 'N'] end.join(', ')
    stmt = stmt << set << where

    validate_privs privs, all_privs
    mysql(mysql_args("mysql", "-Be", stmt))
    mysql_flush
  end

  def validate_privs(set_privs, all_privs)
    all_privs = all_privs.collect { |p| p.downcase }
    set_privs = set_privs.collect { |p| p.downcase }
    invalid_privs = Array.new
    hints = Array.new
    # Test each of the user provided privs to see if they exist in all_privs
    set_privs.each do |priv|
      invalid_privs << priv unless all_privs.include?(priv)
      hints << "#{priv}_priv" if all_privs.include?("#{priv}_priv")
    end
    unless invalid_privs.empty?
      # Print a decently helpful and gramatically correct error message
      hints = "Did you mean '#{hints.join(',')}'?" unless hints.empty?
      p = invalid_privs.size > 1 ? ['s', 'are not valid'] : ['', 'is not valid']
      detail = ["The privilege#{p[0]} '#{invalid_privs.join(',')}' #{p[1]}."]
      fail [detail, hints].join(' ')
    end
  end
end
