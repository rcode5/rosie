require 'find'
require 'fileutils'
require 'tmpdir'
require 'yaml'

rosie_config = {}
ts = nil
db_backup_dir = nil

def get_db_config
  alldbconf = YAML.load_file( File.join( [Rails.root, 'config','database.yml' ] ))
  env = Rails.env
  alldbconf[env]
end

def get_db_cmdline_args
  dbcnf = get_db_config
  args = []
  # NOTE: Assuming that database is running on localhost
  # TODO - if you use other args like :socket, or ? they are ignored
  # we could add host, port etc to make this more flexible
  [['--user=','username'], ['--password=','password']].each do |entry|
    if dbcnf[entry[1]].present?
      args << "#{entry[0]}#{dbcnf[entry[1]]}"
    end
  end
  args
end

namespace :rosie do
  task :init do
    rosie_config = Rosie::Config.new
    db_backup_dir = File.join([Rails.root, rosie_config.backup_dir])
  end

  desc "restore data from backup tarball"
  task :restore => :init do
    puts "Restoring data..."    
    tarball = ENV["datafile"]
    if tarball.present? 
      tmp = File.join(Dir.tmpdir, "rosie-restore")
      FileUtils.remove_dir(tmp, true)
      FileUtils.mkdir_p(tmp)
      if !Dir.exists?(tmp) 
        msg = "Unable to create a temporary directory.  Please check your file permissions.\nAttempted to create #{tmp}"
        raise msg
      end
      files_before = Dir.entries(tmp)
      sh "cd #{tmp} && tar -xzf #{tarball}"
      ts = Dir.entries(tmp).reject{ |f| files_before.include? f }.first
      unless ts.present?
        puts "*** Something went wrong while trying to unpack the datafile."
        exit 1
      end
      dbcnf = get_db_config
      data_dir = File.join(tmp, ts)
      image_tarball = File.join(data_dir, Dir.entries(data_dir).select{|f| f =~ /#{ts}.*\.tar/}.first)
      sql_dump = File.join(data_dir, Dir.entries(data_dir).select{|f| f =~ /#{ts}.*\.sql/}.first)
      args = get_db_cmdline_args
      assets_dir = File.join(Rails.root, rosie_config.assets_dir)
      sh "tar -C #{assets_dir} -xf #{image_tarball} && mysql #{args.join(' ')} #{dbcnf['database']} < #{sql_dump}"
      
    else
      puts "*** You must specify the datafile from which to restore"
      puts "*** e.g.  % datafile=/home/me/2011010101.tgz rake rosie:restore"
      exit 1
    end
  end

  desc "backup all data"
  task :backup => ["rosie:backups:db", "rosie:backups:assets"] do
    sh "cd #{db_backup_dir}/../ && tar -czvf #{ts}.tgz ./#{ts} && rm -rf #{ts}"
  end

  namespace :backups do
    task :init => 'rosie:init' do
      ts = Time.now.strftime('%Y%m%d%H%m%S')
    end

    task :db => :init do
      dbcnf = get_db_config
      db_file = "#{dbcnf['database']}-#{ts}.backup.sql"
      path = File.join(db_backup_dir, db_file)
      args = get_db_cmdline_args
      sh "mkdir -p #{db_backup_dir} && mysqldump #{args.join(' ')} --single-transaction #{dbcnf['database']} > #{path}"
    end

    desc "backup assets in public/system/"
    task :assets => :init do
      assets_dir = File.join(Rails.root, rosie_config.assets_dir)
      sh "tar -C #{assets_dir} -cvf #{db_backup_dir}/rosie_backup_#{Rails.env}_#{ts}.tar ."
    end

  end
  
end

