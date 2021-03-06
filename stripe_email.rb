require 'rubygems'
require 'gdocs4ruby'
require 'logger'
require 'mail'
require 'time'

:$.unshift(File.expand_path(__FILE__))
require 'stripe_store'


# Class StripeEmail
# Stores data using pstore, initializes pad, and can be used to query pad
class StripeEmail
    # Config
    @@config = YAML.load(File.open('/var/stripe/edits-benedict/edits-benedict-cred.conf'))
    log_file = @@config['log']
    @@log = Logger.new(log_file)

    attr_reader :pad_id, :last_modified, :content, :created_at, :mail, :argv, :editors

    # Updates class variables last_modified and content
    def query_pad
        doc = GDocs4Ruby::Document.find(@service, { :id => @pad_id })
        @content = doc.get_content('txt')
        @last_modified = Time.parse(doc.updated)
    end

    # Initialize instance variables
    def initialize(mail, argv)

        @admin = @@config['users']['admin']
        @editors = @@config['users']['editors'].join(',')

        @created_at = Time.new
        @mail = mail
        @mail_str = mail.to_s
        @argv = argv
    end
    
    # Initialize a pad with @mail.body, store it locally, and send
    # the email to admins
    def initialize_pad()

        @@log.debug "Authenticating to Google docs."
        # Initialize the GDocs4Ruby service and authenticate
        @service = GDocs4Ruby::Service.new()
        email = @@config['gdocs-credentials']['username']
        password = @@config['gdocs-credentials']['password']
        @service.authenticate(email, password)

        @@log.debug "Initializing a new Google Document."

        # Populate google doc
        doc = GDocs4Ruby::Document.new(@service)
        doc.title = "Email Review: #{@mail.subject}"
        doc.content = @mail.body.to_s
        doc.content_type = 'txt'
        doc.save

        # Get the id of the document for future use
        pad_id = doc.id
        # Strip out the "document:" that the gem prefixes before the id
        pad_id.slice!('document:')
        @pad_id = pad_id
        @editors.each { |email| doc.add_access_rule(email, 'writer') }
        @@log.debug "Google Document initialized with pad_id: #{pad_id}"

        # Store email in pstore
        store()

        # Send the email to admin
        send_admin_email()
    end
    
    # Store the email locally
    def store()
        StripeStore.new.insert(self)
    end

    # Send email to admins notifying them of the Google Doc ID
    def send_admin_email()
        admin_email_from = @admin
        admin_email_body = sprintf(@@config['email']['body'], @mail.from, generate_url, @mail.body)
        admin_email_subject = @@config['email']['subject_prefix'] + " #{@subject}"
        editors = @editors
        admin_email = Mail.new do
            from admin_email_from
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
