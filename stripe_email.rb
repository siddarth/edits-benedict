require 'rubygems'
require 'gdocs4ruby'
require 'logger'
require 'mail'
require 'StripeStore'
require 'time'

# Class StripeEmail
# Stores data using pstore, initializes pad, and can be used to query pad
class StripeEmail
    @@log = Logger.new('/var/stripe/edits-benedict/edits-benedict.log')

	attr_accessor :from, :to, :subject, :body, :admin, :mail_str
	attr_reader :pad_id, :last_modified, :content, :created_at, :mail, :argv

    # Updates class variables last_modified and content
    def query_pad
        doc = GDocs4Ruby::Document.find(@service, { :id => @pad_id })
        @content = doc.get_content('txt')
        @last_modified = Time.parse(doc.updated)
    end

    # Initialize class variables and populate etherpad
	def initialize(mail, argv)

        # Config
        @@config = YAML.load(File.open('/var/stripe/edits-benedict/edits-benedict-cred.conf'))
	    @admin = @@config['users']['admin']
	    @editors = @@config['users']['editors']

        @created_at = Time.new
        @mail = mail
        @mail_str = mail.to_s
        @argv = argv

        # Initialize the GDocs4Ruby service and authenticate
        @service = GDocs4Ruby::Service.new()
        email = @@config['gdocs-credentials']['username']
        password = @@config['gdocs-credentials']['password']
        @service.authenticate(email, password)

        # Initialize Google doc
	    @pad_id = initialize_pad()

        # Store email in pstore
	    store()

        # Send the email to admin
	    send_admin_email()
	end
	
    # Initialize a pad with @body
    def initialize_pad()
        @@log.debug "Initializing a new Google Document."
        doc = GDocs4Ruby::Document.new(@service)
        doc.title = "Email Review: #{@mail.subject}"
        doc.content = @mail.body.to_s
        doc.content_type = 'txt'
        doc.save
        # XXX: Here comes a small hack.
        pad_id = doc.id[9..-1]
        @editors.each { |email| doc.add_access_rule(email, 'writer') }
        @@log.debug "Google Document initialized: #{pad_id}"
        return pad_id
    end
	
	# Store the email locally
	def store()
        StripeStore.new.insert(self)
    end

    # Send email to admins notifying them of the email ID
	def send_admin_email()
	    admin_email_body = sprintf(@@config['email']['body'], @mail.from, generate_url, @mail.body)
        admin_email_subject = sprintf(@@config['email']['subject_prefix'], @subject)
        editors = @editors.join(',')
	    admin_email = Mail.new do
            from "bot@stripe.com"
            to editors
            subject admin_email_subject
            body admin_email_body
        end
        
        admin_email.deliver!    
	end
	
	# Generate URL for the export pages of different formats
	def generate_url
	    "https://docs.google.com/document/d/#{@pad_id}/edit?hl=en#"
    end
end