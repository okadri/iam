require 'rubygems'
require 'bundler/setup'
Bundler.require

require 'net/http'
require 'json'
require 'yaml'
load 'UcdLookups.rb'
IAM_SETTINGS_FILE = "config/iam.yml"
DSS_RM_FILE = "config/dss_rm.yml"

### Import the IAM site and key from the yaml file
if File.file?(IAM_SETTINGS_FILE)
  $IAM_SETTINGS = YAML.load_file(IAM_SETTINGS_FILE)
  @site = $IAM_SETTINGS['HOST']
  @key = $IAM_SETTINGS['KEY']
  @iamId = ARGV[0]
else
  puts "You need to set up config/iam.yml before running this application."
  exit
end

### Import the DSS RM site and key from the yaml file
if File.file?(DSS_RM_FILE)
  $DSS_RM_SETTINGS = YAML.load_file(DSS_RM_FILE)
else
  puts "You need to set up config/dss_rm.yml before running this application."
  exit
end

require './models/entity.rb'
require './models/person.rb'

### Method to get individual info
def fetch_by_iamId(id)
  ## First, fetch the person
  url = "#{@site}iam/people/search/?iamId=#{id}&key=#{@key}&v=1.0"
  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))
  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  first = result["responseData"]["results"][0]["dFirstName"]
  middle = result["responseData"]["results"][0]["oMiddleName"]
  last = result["responseData"]["results"][0]["dLastName"]
  isEmployee = result["responseData"]["results"][0]["isEmployee"]
  isFaculty = result["responseData"]["results"][0]["isFaculty"]
  isStudent = result["responseData"]["results"][0]["isStudent"]
  isStaff = result["responseData"]["results"][0]["isStaff"]

  ## Second, fetch the contact info
  url = "#{@site}iam/people/contactinfo/#{id}?key=#{@key}&v=1.0"
  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))
  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  email = result["responseData"]["results"][0]["email"]
  phone = result["responseData"]["results"][0]["workPhone"]
  address = result["responseData"]["results"][0]["postalAddress"]

  ## Third, fetch the kerberos userid
  url = "#{@site}iam/people/prikerbacct/#{id}?key=#{@key}&v=1.0"
  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))
  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  loginid = result["responseData"]["results"][0]["userId"]

  ## Forth, fetch the association
  url = "#{@site}iam/associations/pps/search?iamId=#{id}&key=#{@key}&v=1.0"
  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))
  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  dept = result["responseData"]["results"][0]["deptOfficialName"]
  title = result["responseData"]["results"][0]["titleOfficialName"]
  positionType = result["responseData"]["results"][0]["positionType"]



  ## Display the results (Or insert them in database)
  rm = Person.find(loginid)
  puts "IAM_ID: #{id} --> RM_ID #{rm.id} (#{first} #{last}):".cyan

  #Comparing First Name
  if first == rm.first
    comparison = "matches".green
  else
    comparison = "differs: IAM (#{first}), RM (#{rm.first})".red
  end
  puts "\t- First name #{comparison}"

  #Comparing Last Name
  if last == rm.last
    comparison = "matches".green
  else
    comparison = "differs: IAM (#{last}), RM (#{rm.last})".red
  end
  puts "\t- Last name #{comparison}"

  #Comparing Title
  if title == rm.title
    comparison = "matches".green
  else
    comparison = "differs: IAM (#{title}), RM (#{rm.title})".red
  end
  puts "\t- Title #{comparison}"

end


# In case you receive SSL certificate verification errors
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

total = 0
timestamp_start = Time.now

### In case no arguments are provided, we fetch for all people in UcdLookups departments
if @iamId.nil?
  for d in UcdLookups::DEPT_CODES.keys()

    ## Fetch department members
    url = "#{@site}iam/associations/pps/search?deptCode=#{d}&key=#{@key}&v=1.0"

    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))

    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    total += result["responseData"]["results"].length.to_i

    # loop over members
    result["responseData"]["results"].each do |p|
      fetch_by_iamId(p['iamId'])
    end

  end
else
  fetch_by_iamId(@iamId)
  total = 1
end

timestamp_finish = Time.now

puts "Finished processing a total of #{total}. Time elapsed: " + Time.at(timestamp_finish - timestamp_start).gmtime.strftime('%R:%S')