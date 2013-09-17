require 'rubygems'
require 'bundler/setup'
require 'net/http'
require 'json'
require 'yaml'

# In case you receive SSL certificate verification errors
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

Bundler.require

load 'UcdLookups.rb'

IAM_SETTINGS_FILE = "config/iam.yml"
DSS_RM_FILE = "config/dss_rm.yml"

@total = @successfullyCompared = @notFound = @erroredOut = @noKerberos = 0
timestamp_start = Time.now

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
def fetch_by_iamId(id,rm_id)
  begin
    ## Fetch the person
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

    ## Fetch the contact info
    url = "#{@site}iam/people/contactinfo/#{id}?key=#{@key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    email = result["responseData"]["results"][0]["email"]
    phone = result["responseData"]["results"][0]["workPhone"]
    address = result["responseData"]["results"][0]["postalAddress"]

    ## Fetch the kerberos userid
    url = "#{@site}iam/people/prikerbacct/#{id}?key=#{@key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    begin
      loginid = result["responseData"]["results"][0]["userId"]
    rescue
      puts "ID# #{id} does not have a loginId in IAM".light_red
    end

    ## Fetch the association
    url = "#{@site}iam/associations/pps/search?iamId=#{id}&key=#{@key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    associations = result['responseData']['results']


    ## Fetch the student associations
    url = "#{@site}iam/associations/sis/#{id}?key=#{@key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    student_associations = result['responseData']['results']


    ## Display the results (Or insert them in database)
    rm = Person.find(rm_id)
    puts "IAM_ID: #{id} --> RM_ID #{rm_id} (#{rm.first} #{rm.last}):".cyan

    # Comparing First Name
    if first == rm.first
      comparison = "matches".green
    else
      comparison = "differs: IAM (#{first}), RM (#{rm.first})".yellow 
    end
    puts "\t- First name #{comparison}"

    # Comparing Last Name
    if last == rm.last
      comparison = "matches".green
    else
      comparison = "differs: IAM (#{last}), RM (#{rm.last})".yellow 
    end
    puts "\t- Last name #{comparison}"

    # Comparing Email
    if email == rm.email
      comparison = "matches".green
    else
      comparison = "differs: IAM (#{email}), RM (#{rm.email})".yellow 
    end
    puts "\t- Email #{comparison}"

    # Comparing Phone
    unless phone.nil? or rm.phone.nil?
      if phone.gsub(/[^0-9]/,'') == rm.phone.gsub(/[^0-9]/,'')
        comparison = "matches".green
      else
        comparison = "differs: IAM (#{phone}), RM (#{rm.phone})".yellow 
      end
      puts "\t- Phone #{comparison}"
    end

    # Comparing Address
    if address == rm.address
      comparison = "matches".green
    else
      comparison = "differs: IAM (#{address}), RM (#{rm.address})".yellow 
    end
    puts "\t- Address #{comparison}"

    # Comparing Associations
    rm_depts = rm.group_memberships.select{ |x| x.ou == true }.collect(&:name).map(&:downcase)
    associations.each do |a|
      if rm_depts.include?(a["deptOfficialName"].downcase)
        comparison = "exists".green
      else
        comparison = "differs RM (#{rm_depts})".yellow 
      end
      puts "\t- #{a['deptOfficialName']} #{comparison}"
      if a["titleOfficialName"] == rm.title
        comparison = "matches".green
      else
        comparison = "differs: IAM (#{a['titleOfficialName']}), RM (#{rm.title})".yellow 
      end
      puts "\t\t- Title #{comparison}"
    end

    # Comparing Student Associations
    student_associations.each do |a|
      if rm_depts.include?(a["majorName"].downcase)
        comparison = "exists".green
      else
        comparison = "differs RM (#{rm_depts})".yellow 
      end
      puts "\t- #{a['majorName']} #{comparison}"
      if a["levelName"] == rm.title
        comparison = "matches".green
      else
        comparison = "differs: IAM (#{a['levelName']}), RM (#{rm.title})".yellow 
      end
      puts "\t\t- Title #{comparison}"
    end
    
    # Comparing affiliations
    if rm.affiliations.collect(&:name).map { |a| a.split(":").first }.include?("faculty") == isFaculty
      puts "\t- Faculty Status: matches (#{isFaculty})".green
    else
      puts "\t- Faculty Status: differs IAM (#{isFaculty})".yellow
    end
    if rm.affiliations.collect(&:name).map { |a| a.split(":").first }.include?("staff") == isStaff
      puts "\t- Staff Status: matches (#{isStaff})".green
    else
      puts "\t- Staff Status: differs IAM (#{isStaff})".yellow
    end
    if rm.affiliations.collect(&:name).map { |a| a.split(":").first }.include?("student") == isStudent
      puts "\t- Student Status: matches (#{isStudent})".green
    else
      puts "\t- Student Status: differs IAM (#{isStudent})".yellow
    end
    
    @successfullyCompared += 1
  rescue StandardError => e
    puts "Cannot process ID#: #{id} -- #{e.message} #{e.backtrace.inspect}".light_red
    @erroredOut += 1
  end
end


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

    # loop over members
    result["responseData"]["results"].each do |p|
      @total += 1
      iamID = p["iamId"]
      url = "#{@site}iam/people/prikerbacct/#{iamID}?key=#{@key}&v=1.0"
      # Fetch URL
      resp = Net::HTTP.get_response(URI.parse(url))
      # Parse results
      buffer = resp.body
      result = JSON.parse(buffer)

      begin
        loginid = result["responseData"]["results"][0]["userId"]
        person = Person.find(loginid)
        fetch_by_iamId(iamID,person.id)
      rescue
        @noKerberos += 1
        puts "ID# #{iamID} does not have a loginId in IAM".light_red
      end
     end
  end
  for m in UcdLookups::MAJORS.values()
    puts "Processing graduate students in #{m}".magenta
    url = "#{@site}iam/associations/sis/search?collegeCode=GS&majorCode=#{m}&key=#{@key}&v=1.0"
    # Fetch URL
    resp = Net::HTTP.get_response(URI.parse(url))
    # Parse results
    buffer = resp.body
    result = JSON.parse(buffer)

    result["responseData"]["results"].each do |p|
      @total += 1
      iamID = p["iamId"]
      url = "#{@site}iam/people/prikerbacct/#{iamID}?key=#{@key}&v=1.0"
      # Fetch URL
      resp = Net::HTTP.get_response(URI.parse(url))
      # Parse results
      buffer = resp.body
      result = JSON.parse(buffer)
      begin
        loginid = result["responseData"]["results"][0]["userId"]
        person = Person.find(loginid)
        fetch_by_iamId(iamID,person.id)
      rescue
        @noKerberos += 1
        puts "ID# #{iamID} does not have a loginId in IAM".light_red
      end
    end
  end
else
  ## Fetch the kerberos userid
  url = "#{@site}iam/people/prikerbacct/#{@iamId}?key=#{@key}&v=1.0"
  # Fetch URL
  resp = Net::HTTP.get_response(URI.parse(url))
  # Parse results
  buffer = resp.body
  result = JSON.parse(buffer)

  begin
    loginid = result["responseData"]["results"][0]["userId"]
  rescue
    puts "ID# #{@iamId} does not have a loginId in IAM".light_red
    exit
  end

  person = Person.find(loginid)
  fetch_by_iamId(@iamId,person.id)
  @total = 1
end

timestamp_finish = Time.now

puts "\n\nFinished comparing a total of #{@total}:\n"
puts "\t- #{@successfullyCompared} successfully compared.\n"
puts "\t- #{@noKerberos} did not have LoginID in IAM.\n"
puts "\t- #{@notFound} were not found in IAM.\n"
puts "\t- #{@erroredOut} errored out due to some missing fields.\n"
puts "Time elapsed: " + Time.at(timestamp_finish - timestamp_start).gmtime.strftime('%R:%S')
