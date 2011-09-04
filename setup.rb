#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'
require 'open-uri'

include FileUtils

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: setup.rb [options]"

  opts.on("-p", "--httpPort PORT",  "Port for jenkins HTTP Interface") do |p|
    options[:port] = p
  end
  opts.on("-f", "--fake", "Dont actually download, put stuff in a tmp directory, do not register or run - for debugging") do 
    puts "Running in fake mode"
    options[:fake] = true
  end
end.parse!

unless ENV['USER'] == 'root' or options[:fake]
  puts('You need to run this script as root.')
  exit
end


JENKINS_DOWNLOAD_URL = 'http://mirrors.jenkins-ci.org/war/latest/jenkins.war'
jenkins_install_dir = '/Library/Application Support/Jenkins'
jenkins_log_dir = '/Library/Logs/Jenkins'
if options[:fake]
  jenkins_install_dir  = '/tmp/Jenkins'
  jenkins_log_dir      = '/tmp/Library/Logs/Jenkins'
end

JENKINS_WAR_FILE     = File.join( jenkins_install_dir, 'jenkins.war' )
JENKINS_HOME_DIR     = File.join( jenkins_install_dir, 'working_dir' )

def write_file filename, &block
  File.open( filename, 'w', &block )
end

### Setup directories
puts('Creating data and logging directories')
mkdir_p [jenkins_install_dir, JENKINS_HOME_DIR, jenkins_log_dir]

def download_war_file
  ### Download and install the .war file
  puts('Downloading the latest release of Jenkins')
  jenkins_war = open(JENKINS_DOWNLOAD_URL) {|f| f.read }
  raise 'Failed to download Jenkins' if jenkins_war.nil?

  puts('Installing Jenkins')
  write_file(JENKINS_WAR_FILE) { |file| file.write String.new(jenkins_war) }
end

unless options[:fake] 
  download_war_file
end

### Launchd setup
puts('Creating launchd plist')
LAUNCHD_LABEL     = 'org.jenkins-ci.jenkins'
LAUNCHD_DIRECTORY = '/Library/LaunchDaemons'
LAUNCHD_FILE      = "#{LAUNCHD_LABEL}"
LAUNCHD_PATH      = File.join(LAUNCHD_DIRECTORY, LAUNCHD_FILE)

arguments = [ '/usr/bin/java', '-jar', JENKINS_WAR_FILE ]
arguments << "--httpPort=#{options[:port]}" if options.has_key?(:port)
argstr = arguments.join(" ")


puts('Installing launchd plist')

#defaults write launchd_path Label launchd_label
write_launchd_plist = "defaults write " + File.join(jenkins_install_dir, LAUNCHD_FILE)
`#{write_launchd_plist} Label '#{LAUNCHD_LABEL}'`
`#{write_launchd_plist} RunAtLoad -bool 'true'`
`#{write_launchd_plist} EnvironmentVariables -dict JENKINS_HOME #{JENKINS_HOME_DIR}`
`#{write_launchd_plist} StandardOutPath '#{jenkins_log_dir}/jenkins.log'`
`#{write_launchd_plist} StandardErrorPath '#{jenkins_log_dir}/jenkins-error.log'`
`#{write_launchd_plist} Program '/usr/bin/java'`
`#{write_launchd_plist} ProgramArguments -array #{argstr}`
  # @todo Maybe setup Bonjour using the Socket key

if options[:fake]
  exit
end
              
puts('Starting launchd job for Jenkins')
if File::exists?( LAUNCHD_PATH )
  rm LAUNCHD_PATH
end
ln_s File.join(jenkins_install_dir, LAUNCHD_FILE) + ".plist", LAUNCHD_PATH

`sudo launchctl load  #{LAUNCHD_PATH}`
`sudo launchctl start #{LAUNCHD_LABEL}`

puts('Jenkins install complete.')
