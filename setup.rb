#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'
require 'open-uri'

include FileUtils


unless ENV['USER'] == 'root'
  print('You need to run this script as root.')
  exit
end


options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: setup.rb [options]"

  opts.on("-p", "--httpPort PORT",  "Port for jenkins HTTP Interface") do |p|
    options[:port] = p
  end
end.parse!


JENKINS_DOWNLOAD_URL = 'http://mirrors.jenkins-ci.org/war/latest/jenkins.war'
JENKINS_INSTALL_DIR  = '/Library/Application Support/Jenkins'
JENKINS_WAR_FILE     = File.join( JENKINS_INSTALL_DIR, 'jenkins.war' )
JENKINS_HOME_DIR     = File.join( JENKINS_INSTALL_DIR, 'working_dir' )
JENKINS_LOG_DIR      = '/Library/Logs/Jenkins'

def write_file filename, &block
  File.open( filename, 'w', &block )
end


### Setup directories
print('Creating data and logging directories')
mkdir_p [JENKINS_INSTALL_DIR, JENKINS_HOME_DIR, JENKINS_LOG_DIR]


### Download and install the .war file
print('Downloading the latest release of Jenkins')
jenkins_war = open(JENKINS_DOWNLOAD_URL) {|f| f.read }
raise 'Failed to download Jenkins' if jenkins_war.nil?

print('Installing Jenkins')
write_file(JENKINS_WAR_FILE) { |file| file.write String.new(jenkins_war) }

### Launchd setup
print('Creating launchd plist')
LAUNCHD_LABEL     = 'org.jenkins-ci.jenkins'
LAUNCHD_DIRECTORY = '/Library/LaunchDaemons'
LAUNCHD_FILE      = "#{LAUNCHD_LABEL}.plist"
LAUNCHD_PATH      = File.join(LAUNCHD_DIRECTORY, LAUNCHD_FILE)

arguments = [ '/usr/bin/java', '-jar', JENKINS_WAR_FILE ]
arguments << "--httpPort=#{options[:port]}" if options.has_key?(:port)
argstr = arguments.join(" ")


print('Installing launchd plist')

#defaults write launchd_path Label launchd_label
write_launchd_plist = "defaults write " + File.join(JENKINS_INSTALL_DIR, LAUNCHD_FILE)
`#{write_launchd_plist} Label #{LAUNCHD_LABEL}`
`#{write_launchd_plist} RunAtLoad -bool true`
`#{write_launchd_plist} EnvironmentVariables -dict JENKINS_HOME #{JENKINS_HOME_DIR}`
`#{write_launchd_plist} StandardOutPath #{JENKINS_LOG_DIR}/jenkins.log`
`#{write_launchd_plist} StandardErrorPath #{JENKINS_LOG_DIR}/jenkins-error.log`
`#{write_launchd_plist} Program /usr/bin/java`
`#{write_launchd_plist} ProgramArguments -array #{argstr}`
  # @todo Maybe setup Bonjour using the Socket key
              
print('Starting launchd job for Jenkins')
if File::exists?( LAUNCHD_PATH )
  rm LAUNCHD_PATH
end
ln_s File.join(JENKINS_INSTALL_DIR, LAUNCHD_FILE), LAUNCHD_PATH

`sudo launchctl load  #{LAUNCHD_PATH}`
`sudo launchctl start #{LAUNCHD_LABEL}`

print('Jenkins install complete.')
