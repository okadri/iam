require 'net/http'
require 'json'
require 'yaml'
load 'UcdLookups.rb'
IAM_SETTINGS_FILE = "config/iam.yml"

if File.file?(IAM_SETTINGS_FILE)
  $IAM_SETTINGS = YAML.load_file(IAM_SETTINGS_FILE)
  site = $IAM_SETTINGS['HOST']
  key = $IAM_SETTINGS['KEY']
else
  puts "You need to set up config/iam.yml before running this application."
  exit
end


# In case you receive SSL certificate verification errors
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

total = 0
timestamp_start = Time.now

for d in UcdLookups::DEPT_CODES.keys()

  ## Fetch department members
  url = "#{site}iam/associations/pps/search?deptCode=#{d}&key=#{key}&v=1.0"

  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))

  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  total += result["responseData"]["results"].length.to_i

  # loop over members
  result["responseData"]["results"].each do |p|
    ## First, fetch the person
    url = "#{site}iam/people/search/?iamId=#{p['iamId']}&key=#{key}&v=1.0"
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

    ## Second, fetch the association
    url = "#{site}iam/associations/pps/search?iamId=#{p['iamId']}&key=#{key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    dept = result["responseData"]["results"][0]["deptOfficialName"]
    title = result["responseData"]["results"][0]["titleOfficialName"]

    ## Display the results (Or insert them in database)
    puts "#{p['iamId']}: #{first} #{middle} #{last} works for #{dept} as a #{title}"
  end

end


puts "Total = #{total}"
timestamp_finish = Time.now

puts "Finished IAM import. Time elapsed: " + Time.at(timestamp_finish - timestamp_start).gmtime.strftime('%R:%S')