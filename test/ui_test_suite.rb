require 'rubygems'
require 'test/unit'
require 'selenium-webdriver'

# Test suite that exercises functionality through simulating user interactions via Webdriver
#
# REQUIREMENTS
#
# This test suite must be run from outside of Docker (i.e. your host machine) as Docker vms have no concept of browsers/screen output
# Therefore, the following languages/packages must be installed on your host:
#
# 1. RVM (or equivalent Ruby language management system)
# 2. Ruby >= 2.3
# 3. Gems: rubygems, test-unit, selenium-webdriver (see Gemfile.lock for version requirements)
# 4. Google Chrome with at least 2 Google accounts already signed in (referred to as $test_email & $share_email)
# 5. Chromedriver (https://sites.google.com/a/chromium.org/chromedriver/); make sure the verison you install works with your version of chrome
# 6. Register for FireCloud (https://portal.firecloud.org) for both Google accounts (needed for auth & sharing acls)

# USAGE
#
# ui_test_suite.rb takes six arguments:
# 1. path to your Chrome user profile on your system (passed with -p=)
# 2. path to your Chromedriver binary (passed with -c=)
# 3. test email account (passed with -e=); this must be a valid Google & FireCloud user and already signed into Chrome
# 4. share email account (passed with -s=); this must be a valid Google & FireCloud user and already signed into Chrome
# 5. test order (passed with -o=); defaults to defined order (can be alphabetic or random, but random will most likely fail horribly
# 6. download directory (passed with -d=); place where files are downloaded on your OS, defaults to standard OSX location (/Users/`whoami`/Downloads)
# these must be passed with ruby test/ui_test_suite.rb -- -p=[/path/to/profile/dir] -c=[/path/to/chromedriver] -e=[test_email] -s=[share_email] -d=[/path/to/download/dir]
# if you do not use -- before the argument and give the appropriate flag (with =), it is processed as a Test::Unit flag and ignored
#
# Tests can be run singly or in groups by passing -n /pattern/ before the -- on the command line.  This will run any tests that match
# the given pattern.  You can run all 'front-end' and 'admin' tests this way (although front-end tests require the tests studies to have been created already)
#
# Lastly, these tests generate on the order of ~20 emails per complete run.

## INITIALIZATION

# DEFAULTS
$user = `whoami`.strip
$profile_dir = "/Users/#{$user}/Library/Application Support/Google/Chrome/Default"
$chromedriver_path = '/usr/local/bin/chromedriver'
$usage = 'ruby test/ui_test_suite.rb -- -p=/path/to/profile -c=/path/to/chromedriver -e=testing.email@gmail.com -s=sharing.email@gmail.com -o=order -d=/path/to/downloads'
$test_email = ''
$share_email = ''
$order = 'defined'
$download_dir = "/Users/#{$user}/Downloads"

# parse arguments
ARGV.each do |arg|
	if arg =~ /\-p\=/
		$profile_dir = arg.gsub(/\-p\=/, "")
	elsif arg =~ /\-c\=/
	 	$chromedriver_path = arg.gsub(/\-c\=/, "")
	elsif arg =~ /\-e\=/
		$test_email = arg.gsub(/\-e\=/, "")
	elsif arg =~ /\-s\=/
		$share_email = arg.gsub(/\-s\=/, "")
	elsif arg =~ /\-o\=/
		$order = arg.gsub(/\-o\=/, "").to_sym
	elsif arg =~ /\-d\=/
		$download_dir = arg.gsub(/\-d\=/, "")
	end
end

# print configuration
puts "Loaded Chrome Profile: #{$profile_dir}"
puts "Chromedriver Binary: #{$chromedriver_path}"
puts "Testing email: #{$test_email}"
puts "Sharing email: #{$share_email}"
puts "Download directory: #{$download_dir}"

# make sure profile & chromedriver exist, otherwise kill tests before running and print usage
if !Dir.exists?($profile_dir)
	puts "No Chrome profile found at #{$profile_dir}"
	puts $usage
	exit(1)
elsif !File.exists?($chromedriver_path)
	puts "No Chromedriver binary found at #{$chromedriver_path}"
	puts $usage
	exit(1)
elsif !Dir.exists?($download_dir)
	puts "No download directory found at #{$download_dir}"
	puts $usage
	exit(1)
end

class UiTestSuite < Test::Unit::TestCase
	self.test_order = $order

	def setup
		@driver = Selenium::WebDriver::Driver.for :chrome, driver_path: $chromedriver_dir, switches: ["--user-data-dir=#{$profile_dir}", '--enable-webgl-draft-extensions']
		@driver.manage.window.maximize
		@base_url = 'https://localhost/single_cell'
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 15
		# only Google auth

		@genes = %w(Itm2a Sergef Chil5 Fam109a Dhx9 Ssu72 Olfr1018 Fam71e2 Eif2b2)
		@wait = Selenium::WebDriver::Wait.new(:timeout => 30)
		@test_data_path = File.expand_path(File.join(File.dirname(__FILE__), 'test_data')) + '/'
		@base_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))
		puts "\n"
	end

	def teardown
		@driver.quit
	end

	# return true/false if element is present in DOM
	def element_present?(how, what)
		@driver.find_element(how, what)
		true
	rescue Selenium::WebDriver::Error::NoSuchElementError
		false
	end

	# explicit wait until requested page loads
	def wait_until_page_loads(path)
		@wait.until { @driver.execute_script('return PAGE_RENDERED;') == true }
		puts "#{path} successfully loaded"
	end

	# method to close a bootstrap modal by id
	def close_modal(id)
		modal = @driver.find_element(:id, id)
		dismiss = modal.find_element(:class, 'close')
		dismiss.click
		# this is a hack, but different browsers behave differently so this lets the fade animation clear
		sleep(1)
	end

	# wait until element is rendered and visible
	def wait_for_render(how, what)
		@wait.until {@driver.find_element(how, what).displayed? == true}
	end

	# wait until plotly chart has finished rendering
	def wait_for_plotly_render(plot, data_id)
		i = 1
		i.upto(10) do
			done = @driver.execute_script("return $('#{plot}').data('#{data_id}')")
			if !done
				puts "Waiting for render of #{plot} - rendered currently: #{done}; try ##{i}"
				i += 1
				sleep(1)
				next
			else
				puts "Rendering of #{plot} complete"
				return true
			end
		end
		raise Selenium::WebDriver::Error::TimeOutError, "Timing out on render check of #{plot}"
	end

	# scroll to bottom of page as needed
	def scroll_to_bottom
		@driver.execute_script('window.scrollBy(0,1000)')
		sleep(1)
	end

	# helper to log into admin portion of site
	# Will also approve terms if not accepted yet, waits for redirect back to site, and closes modal
	def login(email)
		google_auth = @driver.find_element(:id, 'google-auth')
		google_auth.click
		puts 'logging in as ' + email
		account = @driver.find_element(xpath: "//button[@value='#{email}']")
		account.click
		# check to make sure if we need to accept terms
		if @driver.current_url.include?('https://accounts.google.com/o/oauth2/auth')
			puts 'approving access'
			approve = @driver.find_element(:id, 'submit_approve_access')
			@clickable = approve['disabled'].nil?
			while @clickable != true
				sleep(1)
				@clickable = @driver.find_element(:id, 'submit_approve_access')['disabled'].nil?
			end
			approve.click
			puts 'access approved'
		end
		# wait for redirect to finish by checking for footer element
		@not_loaded = true
		while @not_loaded == true
			begin
				# we need to return the result of the script to store its value
				loaded = @driver.execute_script("return elementVisible('.footer')")
				if loaded == true
					@not_loaded = false
				end
				sleep(1)
			rescue Selenium::WebDriver::Error::UnknownError
				sleep(1)
			end
		end
		close_modal('message_modal')
		puts 'login successful'
	end

	##
	## ADMIN TESTS
	##

	# admin backend tests of entire study creation process including negative/error tests
	# uses example data in test directoyr as inputs (based off of https://github.com/broadinstitute/single_cell_portal/tree/master/demo_data)
	# these tests run first to create test studies to use in front-end tests later
	test 'admin: create a study' do
		puts "Test method: #{self.method_name}"

		# log in first
		path = @base_url + '/studies/new'
		@driver.get path
		close_modal('message_modal')
		# log in as user #1
		login($test_email)

		# fill out study form
		study_form = @driver.find_element(:id, 'new_study')
		study_form.find_element(:id, 'study_name').send_keys('Test Study')
		study_form.find_element(:id, 'study_embargo').send_keys('2016-12-31')
		public = study_form.find_element(:id, 'study_public')
		public.send_keys('Yes')
		# add a share
		share = @driver.find_element(:id, 'add-study-share')
		@wait.until {share.displayed?}
		share.click
		share_email = study_form.find_element(:class, 'share-email')
		share_email.send_keys($share_email)
		share_permission = study_form.find_element(:class, 'share-permission')
		share_permission.send_keys('Edit')
		# save study
		save_study = @driver.find_element(:id, 'save-study')
		save_study.click

		# upload expression matrix
		close_modal('message_modal')
		upload_expression = @driver.find_element(:id, 'upload-expression')
		upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload metadata
		wait_for_render(:id, 'metadata_form')
		upload_metadata = @driver.find_element(:id, 'upload-metadata')
		upload_metadata.send_keys(@test_data_path + 'metadata_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload cluster
		cluster_form_1 = @driver.find_element(:class, 'initialize_ordinations_form')
		cluster_name = cluster_form_1.find_element(:class, 'filename')
		cluster_name.send_keys('Test Cluster 1')
		upload_cluster = cluster_form_1.find_element(:class, 'upload-clusters')
		upload_cluster.send_keys(@test_data_path + 'cluster_example.txt')
		wait_for_render(:id, 'start-file-upload')
		# add labels and axis ranges
		cluster_form_1.find_element(:id, :study_file_x_axis_min).send_key(-100)
		cluster_form_1.find_element(:id, :study_file_x_axis_max).send_key(100)
		cluster_form_1.find_element(:id, :study_file_y_axis_min).send_key(-75)
		cluster_form_1.find_element(:id, :study_file_y_axis_max).send_key(75)
		cluster_form_1.find_element(:id, :study_file_z_axis_min).send_key(-125)
		cluster_form_1.find_element(:id, :study_file_z_axis_max).send_key(125)
		cluster_form_1.find_element(:id, :study_file_x_axis_label).send_key('X Axis')
		cluster_form_1.find_element(:id, :study_file_y_axis_label).send_key('Y Axis')
		cluster_form_1.find_element(:id, :study_file_z_axis_label).send_key('Z Axis')
		# perform upload
		upload_btn = cluster_form_1.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload a second cluster
		prev_btn = @driver.find_element(:id, 'prev-btn')
		prev_btn.click
		new_cluster = @driver.find_element(:class, 'add-cluster')
		new_cluster.click
		sleep(1)
		scroll_to_bottom
		# will be second instance since there are two forms
		cluster_form_2 = @driver.find_element(:class, 'new-cluster-form')
		cluster_name_2 = cluster_form_2.find_element(:class, 'filename')
		cluster_name_2.send_keys('Test Cluster 2')
		upload_cluster_2 = cluster_form_2.find_element(:class, 'upload-clusters')
		upload_cluster_2.send_keys(@test_data_path + 'cluster_2_example.txt')
		wait_for_render(:id, 'start-file-upload')
		scroll_to_bottom
		upload_btn_2 = cluster_form_2.find_element(:id, 'start-file-upload')
		upload_btn_2.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload fastq
		wait_for_render(:class, 'initialize_fastq_form')
		upload_fastq = @driver.find_element(:class, 'upload-fastq')
		upload_fastq.send_keys(@test_data_path + 'cell_1_L1.fastq.gz')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:class, 'fastq-file')
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click

		# upload marker gene list
		wait_for_render(:class, 'initialize_marker_genes_form')
		marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
		marker_file_name = marker_form.find_element(:id, 'study_file_name')
		marker_file_name.send_keys('Test Gene List')
		upload_markers = marker_form.find_element(:class, 'upload-marker-genes')
		upload_markers.send_keys(@test_data_path + 'marker_1_gene_list.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = marker_form.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click

		# upload doc file
		wait_for_render(:class, 'initialize_misc_form')
		upload_doc = @driver.find_element(:class, 'upload-misc')
		upload_doc.send_keys(@test_data_path + 'table_1.xlsx')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:class, 'documentation-file')
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# change attributes on file to validate update function
		misc_form = @driver.find_element(:class, 'initialize_misc_form')
		desc_field = misc_form.find_element(:id, 'study_file_description')
		desc_field.send_keys('Supplementary table')
		save_btn = misc_form.find_element(:class, 'save-study-file')
		save_btn.click
		wait_for_render(:id, 'study-file-notices')
		close_modal('study-file-notices')
		puts "Test method: #{self.method_name} successful!"
	end

	# verify that recently created study uploaded to firecloud
	test 'admin: verify firecloud workspace' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/studies'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		show_study = @driver.find_element(:class, 'test-study-show')
		show_study.click

		# verify firecloud workspace creation
		firecloud_link = @driver.find_element(:id, 'firecloud-link')
		firecloud_url = 'https://portal.firecloud.org/#workspaces/single-cell-portal%3Adevelopment-test-study'
		firecloud_link.click
		@driver.switch_to.window(@driver.window_handles.last)
		assert @driver.current_url == firecloud_url, 'did not open firecloud workspace'
		completed = @driver.find_elements(:class, 'fa-check-circle')
		assert completed.size >= 1, 'did not provision workspace properly'

		# verify gcs bucket and uploads
		@driver.switch_to.window(@driver.window_handles.first)
		gcs_link = @driver.find_element(:id, 'gcs-link')
		gcs_link.click
		@driver.switch_to.window(@driver.window_handles.last)
		files = @driver.find_elements(:class, 'p6n-clickable-row')
		assert files.size == 7, "did not find correct number of files, expected 7 but found #{files.size}"
		puts "Test method: #{self.method_name} successful!"
	end

	# test to verify deleting files removes them from gcs buckets
	test 'admin: delete study file' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/studies'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		add_files = @driver.find_element(:class, 'test-study-upload')
		add_files.click
		misc_tab = @driver.find_element(:id, 'initialize_misc_form_nav')
		misc_tab.click

		# test abort functionality first
		add_misc = @driver.find_element(:class, 'add-misc')
		add_misc.click
		new_misc_form = @driver.find_element(:class, 'new-misc-form')
		upload_doc = new_misc_form.find_element(:class, 'upload-misc')
		upload_doc.send_keys(@test_data_path + 'README.txt')
		wait_for_render(:id, 'start-file-upload')
		cancel = @driver.find_element(:class, 'cancel')
		cancel.click
		wait_for_render(:id, 'study-file-notices')
		close_modal('study-file-notices')

		# delete file from test study
		form = @driver.find_element(:class, 'initialize_misc_form')
		delete = form.find_element(:class, 'delete-file')
		delete.click
		@driver.switch_to.alert.accept
		# wait a few seconds to allow delete call to propogate all the way to FireCloud
		sleep(5)

		@driver.get path
		files = @driver.find_element(:id, 'test-study-study-file-count')
		assert files.text == '6', "did not find correct number of files, expected 6 but found #{files.text}"

		# verify deletion in google
		show_study = @driver.find_element(:class, 'test-study-show')
		show_study.click
		gcs_link = @driver.find_element(:id, 'gcs-link')
		gcs_link.click
		@driver.switch_to.window(@driver.window_handles.last)
		google_files = @driver.find_elements(:class, 'p6n-clickable-row')
		sleep(5)
		assert google_files.size == 6, "did not find correct number of files, expected 6 but found #{google_files.size}"
		puts "Test method: #{self.method_name} successful!"
	end

	# text gzip parsing of expression matrices
	test 'admin: parse gzip expression matrix' do
		puts "Test method: #{self.method_name}"

		# log in first
		path = @base_url + '/studies/new'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		# fill out study form
		study_form = @driver.find_element(:id, 'new_study')
		study_form.find_element(:id, 'study_name').send_keys('Gzip Parse')
		# save study
		save_study = @driver.find_element(:id, 'save-study')
		save_study.click

		# upload bad expression matrix
		close_modal('message_modal')
		upload_expression = @driver.find_element(:id, 'upload-expression')
		upload_expression.send_keys(@test_data_path + 'expression_matrix_example_gzipped.txt.gz')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# verify parse completed
		studies_path = @base_url + '/studies'
		@driver.get studies_path
		wait_until_page_loads(studies_path)
		study_file_count = @driver.find_element(:id, 'gzip-parse-study-file-count')
		assert study_file_count.text == '1', "found incorrect number of study files; expected 1 and found #{study_file_count.text}"
		puts "Test method: #{self.method_name} successful!"
	end

	# negative tests to check file parsing & validation
	# since parsing happens in background, all messaging is handled through emails
	# this test just makes sure that parsing fails and removed entries appropriately
	# your test email account should receive emails notifying of failure
	test 'admin: create study error messaging' do
		puts "Test method: #{self.method_name}"

		# log in first
		path = @base_url + '/studies/new'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		# fill out study form
		study_form = @driver.find_element(:id, 'new_study')
		study_form.find_element(:id, 'study_name').send_keys('Error Messaging Test Study')
		# save study
		save_study = @driver.find_element(:id, 'save-study')
		save_study.click

		# upload bad expression matrix
		close_modal('message_modal')
		upload_expression = @driver.find_element(:id, 'upload-expression')
		upload_expression.send_keys(@test_data_path + 'expression_matrix_example_bad.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload bad metadata assignments
		wait_for_render(:id, 'metadata_form')
		upload_assignments = @driver.find_element(:id, 'upload-metadata')
		upload_assignments.send_keys(@test_data_path + 'metadata_bad.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload bad cluster coordinates
		upload_clusters = @driver.find_element(:class, 'upload-clusters')
		upload_clusters.send_keys(@test_data_path + 'cluster_bad.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click

		# upload bad marker gene list
		marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
		marker_file_name = marker_form.find_element(:id, 'study_file_name')
		marker_file_name.send_keys('Test Gene List')
		upload_markers = @driver.find_element(:class, 'upload-marker-genes')
		upload_markers.send_keys(@test_data_path + 'marker_1_gene_list_bad.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# close modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		# wait for a few seconds to allow parses to fail fully
		sleep(3)

		# assert parses all failed and delete study
		@driver.get(@base_url + '/studies')
		wait_until_page_loads(@base_url + '/studies')
		study_file_count = @driver.find_element(:id, 'error-messaging-test-study-study-file-count')
		assert study_file_count.text == '0', "found incorrect number of study files; expected 0 and found #{study_file_count.text}"
		@driver.find_element(:class, 'error-messaging-test-study-delete').click
		@driver.switch_to.alert.accept
		wait_for_render(:id, 'message_modal')
		close_modal('message_modal')
		puts "Test method: #{self.method_name} successful!"
	end

	# create private study for testing visibility/edit restrictions
	# must be run before other tests, so numbered accordingly
	test 'admin: create private study' do
		puts "Test method: #{self.method_name}"

		# log in first
		path = @base_url + '/studies/new'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		# fill out study form
		study_form = @driver.find_element(:id, 'new_study')
		study_form.find_element(:id, 'study_name').send_keys('Private Study')
		public = study_form.find_element(:id, 'study_public')
		public.send_keys('No')
		# save study
		save_study = @driver.find_element(:id, 'save-study')
		save_study.click
		puts "Test method: #{self.method_name} successful!"
	end

	# check visibility & edit restrictions as well as share access
	# will also verify FireCloud ACL settings on shares
	test 'admin: create share and check view and edit' do
		puts "Test method: #{self.method_name}"

		# check view visibility for unauthenticated users
		path = @base_url + '/study/private-study'
		@driver.get path
		assert @driver.current_url == @base_url, 'did not redirect'
		assert element_present?(:id, 'message_modal'), 'did not find alert modal'
		close_modal('message_modal')

		# log in and get study ids for use later
		path = @base_url + '/studies'
		@driver.get path
		@driver.manage.window.maximize
		close_modal('message_modal')
		# send login info
		login($test_email)

		# get path info
		edit = @driver.find_element(:class, 'private-study-edit')
		edit.click
		sleep(2)
		private_study_id = @driver.current_url.split('/')[5]
		@driver.get @base_url + '/studies'
		edit = @driver.find_element(:class, 'test-study-edit')
		edit.click
		sleep(2)
		share_study_id = @driver.current_url.split('/')[5]

		# logout
		profile = @driver.find_element(:id, 'profile-nav')
		profile.click
		logout = @driver.find_element(:id, 'logout-nav')
		logout.click
		wait_until_page_loads(@base_url)
		close_modal('message_modal')

		# login as share user
		login_link = @driver.find_element(:id, 'login-nav')
		login_link.click
		login($share_email)

		# view study
		path = @base_url + '/study/private-study'
		@driver.get path
		assert @driver.current_url == @base_url, 'did not redirect'
		assert element_present?(:id, 'message_modal'), 'did not find alert modal'
		close_modal('message_modal')
		# check public visibility when logged in
		path = @base_url + '/study/gzip-parse'
		@driver.get path
		assert @driver.current_url == path, 'did not load public study without share'

		# edit study
		edit_path = @base_url + '/studies/' + private_study_id + '/edit'
		@driver.get edit_path
		assert @driver.current_url == @base_url + '/studies', 'did not redirect'
		assert element_present?(:id, 'message_modal'), 'did not find alert modal'
		close_modal('message_modal')

		# test share
		share_view_path = @base_url + '/study/test-study'
		@driver.get share_view_path
		assert @driver.current_url == share_view_path, 'did not load share study view'
		share_edit_path = @base_url + '/studies/' + share_study_id + '/edit'
		@driver.get share_edit_path
		assert @driver.current_url == share_edit_path, 'did not load share study edit'

		# test uploading a file
		upload_path = @base_url + '/studies/' + share_study_id + '/upload'
		@driver.get upload_path
		misc_tab = @driver.find_element(:id, 'initialize_misc_form_nav')
		misc_tab.click

		upload_doc = @driver.find_element(:class, 'upload-misc')
		upload_doc.send_keys(@test_data_path + 'README.txt')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# verify upload has completed and is in FireCloud bucket
		@driver.get @base_url + '/studies/'
		file_count = @driver.find_element(:id, 'test-study-study-file-count')
		assert file_count.text == '7', "did not find correct number of files, expected 7 but found #{file_count.text}"
		show_study = @driver.find_element(:class, 'test-study-show')
		show_study.click
		gcs_link = @driver.find_element(:id, 'gcs-link')
		gcs_link.click
		@driver.switch_to.window(@driver.window_handles.last)
		files = @driver.find_elements(:class, 'p6n-clickable-row')
		assert files.size == 7, "did not find correct number of files, expected 7 but found #{files.size}"
		puts "Test method: #{self.method_name} successful!"
	end

	##
	## FRONT END FUNCTIONALITY TESTS
	##

	test 'front-end: get home page' do
		puts "Test method: #{self.method_name}"

		@driver.get(@base_url)
		assert element_present?(:id, 'main-banner'), 'could not find index page title text'
		assert @driver.find_elements(:class, 'panel-primary').size >= 1, 'did not find any studies'
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: perform search' do
		puts "Test method: #{self.method_name}"

		@driver.get(@base_url)
		search_box = @driver.find_element(:id, 'search_terms')
		search_box.send_keys('Test Study')
		submit = @driver.find_element(:id, 'submit-search')
		submit.click
		studies = @driver.find_elements(:class, 'study-panel').size
		assert studies == 1, 'incorrect number of studies found. expected one but found ' + studies.to_s
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: load Test Study study' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

		# load subclusters
		clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
		assert clusters.size == 2, 'incorrect number of clusters found'
		annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
		assert annotations.size == 5, 'incorrect number of annotations found'
		annotations.select {|opt| opt.text == 'Sub-Cluster'}.first.click

		# wait for render again
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		sub_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert sub_rendered, "cluster plot did not finish rendering on change, expected true but found #{sub_rendered}"
		legend = @driver.find_elements(:class, 'traces').size
		assert legend == 6, "incorrect number of traces found in Sub-Cluster, expected 6 - found #{legend}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: download study data file' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		download_section = @driver.find_element(:id, 'study-data-files')
		# gotcha when clicking, must wait until completes
		download_section.click
		files = @driver.find_elements(:class, 'dl-link')
		file_link = files.last
		filename = file_link['download']
		basename = filename.split('.').first
		@wait.until { file_link.displayed? }
		downloaded = file_link.click
		assert downloaded == nil, 'could not click download link'
		# give browser 2 seconds to initiate download
		sleep(2)
		# make sure file was actually downloaded
		file_exists = Dir.entries($download_dir).select {|f| f =~ /#{basename}/}.size >= 1 || File.exists?(File.join($download_dir, filename))
		assert file_exists, "did not find downloaded file: #{filename} in #{Dir.entries($download_dir).join(', ')}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: search for single gene' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		# load random gene to search
		gene = @genes.sample
		search_box = @driver.find_element(:id, 'search_genes')
		search_box.send_key(gene)
		search_form = @driver.find_element(:id, 'search-genes-form')
		search_form.submit
		assert element_present?(:id, 'box-controls'), 'could not find expression boxplot'
		assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

		# wait until box plot renders, at this point all 3 should be done
		@wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
		box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
		assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
		scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
		assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
		reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
		assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: search for multiple genes' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		# load random genes to search
		genes = @genes.shuffle.take(1 + rand(@genes.size) + 1)
		search_box = @driver.find_element(:id, 'search_genes')
		search_box.send_keys(genes.join(' '))
		search_form = @driver.find_element(:id, 'search-genes-form')
		search_form.submit
		assert element_present?(:id, 'plots'), 'could not find expression heatmap'
		@wait.until {wait_for_plotly_render('#heatmap-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#heatmap-plot').data('rendered')")
		assert rendered, "heatmap plot did not finish rendering, expected true but found #{rendered}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: load marker gene heatmap' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)

		expression_list = @driver.find_element(:id, 'expression')
		opts = expression_list.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
		list = opts.sample
		list.click
		assert element_present?(:id, 'heatmap-plot'), 'could not find heatmap plot'

		# wait for heatmap to render
		@wait.until {wait_for_plotly_render('#heatmap-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#heatmap-plot').data('rendered')")
		assert rendered, "heatmap plot did not finish rendering, expected true but found #{rendered}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: load marker gene box/scatter' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		gene_sets = @driver.find_element(:id, 'gene_set')
		opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
		list = opts.sample
		list.click
		assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'

		# wait until box plot renders, at this point all 3 should be done
		@wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
		box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
		assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
		scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
		assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
		reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
		assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"
		puts "Test method: #{self.method_name} successful!"
	end

	test 'front-end: load different cluster and annotation then search gene expression' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
		cluster = clusters.last
		cluster_name = cluster['text']
		cluster.click

		# wait for render to complete
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		cluster_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert cluster_rendered, "cluster plot did not finish rendering on cluster change, expected true but found #{cluster_rendered}"

		# select an annotation and wait for render
		annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
		annotation = annotations.sample
		annotation_value = annotation['value']
		annotation.click
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

		# now search for a gene and make sure values are preserved
		gene = @genes.sample
		search_box = @driver.find_element(:id, 'search_genes')
		search_box.send_key(gene)
		search_form = @driver.find_element(:id, 'search-genes-form')
		search_form.submit
		new_path = "#{@base_url}/study/test-study/gene_expression/#{gene}?annotation=#{annotation_value.split.join('+')}&boxpoints=all&cluster=#{cluster_name.split.join('+')}"
		wait_until_page_loads(new_path)

		# wait for rendering to complete
		assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'

		@wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
		box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
		assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
		scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
		assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
		reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
		assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

		# now check values
		loaded_cluster = @driver.find_element(:id, 'cluster')
		loaded_annotation = @driver.find_element(:id, 'annotation')
		assert loaded_cluster['value'] == cluster_name, "did not load correct cluster; expected #{cluster_name} but loaded #{loaded_cluster['value']}"
		assert loaded_annotation['value'] == annotation_value, "did not load correct annotation; expected #{annotation_value} but loaded #{loaded_annotation['value']}"
		puts "Test method: #{self.method_name} successful!"
	end

	# test whether or not maintenance mode functions properly
	test 'front-end: enable maintenance mode' do
		puts "Test method: #{self.method_name}"

		# enable maintenance mode
		system("#{@base_path}/bin/enable_maintenance.sh on")
		@driver.get @base_url
		assert element_present?(:id, 'maintenance-notice'), 'could not load maintenance page'
		# disable maintenance mode
		system("#{@base_path}/bin/enable_maintenance.sh off")
		@driver.get @base_url
		assert element_present?(:id, 'main-banner'), 'could not load home page'
		puts "Test method: #{self.method_name} successful!"
	end

	# test that camera position is being preserved on cluster/annotation select & rotation
	test 'front-end: check camera position on change' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

		# get camera data
		camera = @driver.execute_script("return $('#cluster-plot').data('camera');")
		# set new rotation
		camera['eye']['x'] = (Random.rand * 10 - 5).round(4)
		camera['eye']['y'] = (Random.rand * 10 - 5).round(4)
		camera['eye']['z'] = (Random.rand * 10 - 5).round(4)
		# call relayout to trigger update & camera position save
		@driver.execute_script("Plotly.relayout('cluster-plot', {'scene': {'camera' : #{camera.to_json}}});")

		# get new camera
		sleep(1)
		new_camera = @driver.execute_script("return $('#cluster-plot').data('camera');")
		assert camera == new_camera['camera'], "camera position did not save correctly, expected #{camera.to_json}, got #{new_camera.to_json}"
		# load annotation
		annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
		annotations.select {|opt| opt.text == 'Sub-Cluster'}.first.click

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

		# verify camera position was saved
		annot_camera = @driver.execute_script("return $('#cluster-plot').data('camera');")
		assert camera == annot_camera['camera'], "camera position did not save correctly, expected #{camera.to_json}, got #{annot_camera.to_json}"

		# load new cluster
		clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
		cluster = clusters.last
		cluster.click

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		cluster_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert cluster_rendered, "cluster plot did not finish rendering on cluster change, expected true but found #{cluster_rendered}"

		# verify camera position was saved
		cluster_camera = @driver.execute_script("return $('#cluster-plot').data('camera');")
		assert camera == cluster_camera['camera'], "camera position did not save correctly, expected #{camera.to_json}, got #{cluster_camera.to_json}"
		puts "Test method: #{self.method_name} successful!"
	end

	# test that axes are rendering custom domains and labels properly
	test 'front-end: check axis domains and labels' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

		# get layout object from browser and verify labels & ranges
		layout = @driver.execute_script('return layout;')
		assert layout['scene']['xaxis']['range'] == [-100, 100], "X range was not correctly set, expected [-100, 100] but found #{layout['scene']['xaxis']['range']}"
		assert layout['scene']['yaxis']['range'] == [-75, 75], "Y range was not correctly set, expected [-75, 75] but found #{layout['scene']['xaxis']['range']}"
		assert layout['scene']['zaxis']['range'] == [-125, 125], "Z range was not correctly set, expected [-125, 125] but found #{layout['scene']['xaxis']['range']}"
		assert layout['scene']['xaxis']['title'] == 'X Axis', "X title was not set correctly, expected 'X Axis' but found #{layout['scene']['xaxis']['title']}"
		assert layout['scene']['yaxis']['title'] == 'Y Axis', "Y title was not set correctly, expected 'Y Axis' but found #{layout['scene']['yaxis']['title']}"
		assert layout['scene']['zaxis']['title'] == 'Z Axis', "Z title was not set correctly, expected 'Z Axis' but found #{layout['scene']['zaxis']['title']}"
		puts "Test method: #{self.method_name} successful!"
	end

	# test that toggle traces button works
	test 'front-end: check toggle traces button' do
		puts "Test method: #{self.method_name}"

		path = @base_url + '/study/test-study'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

		# wait until cluster finishes rendering
		@wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
		rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
		assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

		# toggle traces off
		toggle = @driver.find_element(:id, 'toggle-traces')
		toggle.click

		# check visiblity
		visible = @driver.execute_script('return data[0].visible')
		assert visible == 'legendonly', "did not toggle trace visibility, expected 'legendonly' but found #{visible}"

		# toggle traces on
		toggle.click

		# check visiblity
		visible = @driver.execute_script('return data[0].visible')
		assert visible == true, "did not toggle trace visibility, expected 'true' but found #{visible}"
		puts "Test method: #{self.method_name} successful!"
	end

	##
	## CLEANUP
	##

	# final test, remove test study that was created and used for front-end tests
	# runs last to clean up data for next test run
	test 'admin: delete all test studies' do
		puts "Test method: #{self.method_name}"

		# log in first
		path = @base_url + '/studies'
		@driver.get path
		close_modal('message_modal')
		login($test_email)

		# delete test
		@driver.find_element(:class, 'test-study-delete').click
		@driver.switch_to.alert.accept
		wait_for_render(:id, 'message_modal')
		close_modal('message_modal')

		# delete private
		@driver.find_element(:class, 'private-study-delete').click
		@driver.switch_to.alert.accept
		wait_for_render(:id, 'message_modal')
		close_modal('message_modal')

		# delete gzip parse
		@driver.find_element(:class, 'gzip-parse-delete').click
		@driver.switch_to.alert.accept
		wait_for_render(:id, 'message_modal')
		close_modal('message_modal')

		puts "Test method: #{self.method_name} successful!"
	end
end