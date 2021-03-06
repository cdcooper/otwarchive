class Collection < ActiveRecord::Base

  attr_protected :description_sanitizer_version

  has_attached_file :icon,
  :styles => { :standard => "100x100>" },
  :url => "/system/:class/:attachment/:id/:style/:basename.:extension",
  :path => Rails.env.production? ? ":class/:attachment/:id/:style.:extension" : ":rails_root/public:url",
  :storage => Rails.env.production? ? :s3 : :filesystem,
  :s3_credentials => "#{Rails.root}/config/s3.yml",
  :bucket => Rails.env.production? ? YAML.load_file("#{Rails.root}/config/s3.yml")['bucket'] : "",
  :default_url => "/images/collection_icon.png"

  validates_attachment_content_type :icon, :content_type => /image\/\S+/, :allow_nil => true
  validates_attachment_size :icon, :less_than => 500.kilobytes, :allow_nil => true

  belongs_to :parent, :class_name => "Collection"
  has_many :children, :class_name => "Collection", :foreign_key => "parent_id"

  has_one :collection_profile, :dependent => :destroy
  accepts_nested_attributes_for :collection_profile

  has_one :collection_preference, :dependent => :destroy
  accepts_nested_attributes_for :collection_preference

  before_create :ensure_associated
  def ensure_associated
    self.collection_preference = CollectionPreference.new unless  self.collection_preference
    self.collection_profile = CollectionProfile.new unless  self.collection_profile
  end


  belongs_to :challenge, :dependent => :destroy, :polymorphic => true
  has_many :prompts, :dependent => :destroy

  has_many :signups, :class_name => "ChallengeSignup", :dependent => :destroy
  has_many :potential_matches, :dependent => :destroy
  has_many :assignments, :class_name => "ChallengeAssignment", :dependent => :destroy
  has_many :claims, :class_name => "ChallengeClaim", :dependent => :destroy

  # We need to get rid of all of these if the challenge is destroyed
  after_save :clean_up_challenge
  def clean_up_challenge
    if self.challenge.nil?
      assignments.each {|assignment| assignment.destroy}
      potential_matches.each {|potential_match| potential_match.destroy}
      signups.each {|signup| signup.destroy}
      prompts.each {|prompt| prompt.destroy}
    end
  end

  has_many :collection_items, :dependent => :destroy
  accepts_nested_attributes_for :collection_items, :allow_destroy => true
  has_many :approved_collection_items, :class_name => "CollectionItem",
    :conditions => ['collection_items.user_approval_status = ? AND collection_items.collection_approval_status = ?', CollectionItem::APPROVED, CollectionItem::APPROVED]

  has_many :works, :through => :collection_items, :source => :item, :source_type => 'Work'
  has_many :approved_works, :through => :collection_items, :source => :item, :source_type => 'Work',
    :conditions => ['collection_items.user_approval_status = ? AND collection_items.collection_approval_status = ? AND works.posted = true', CollectionItem::APPROVED, CollectionItem::APPROVED]
  has_many :bookmarks, :through => :collection_items, :source => :item, :source_type => 'Bookmark'
  has_many :approved_bookmarks, :through => :collection_items, :source => :item, :source_type => 'Bookmark',
    :conditions => ['collection_items.user_approval_status = ? AND collection_items.collection_approval_status = ?', CollectionItem::APPROVED, CollectionItem::APPROVED]
  has_many :fandoms, :through => :approved_works, :uniq => true
  has_many :filters, :through => :approved_works, :uniq => true

  has_many :collection_participants, :dependent => :destroy
  accepts_nested_attributes_for :collection_participants, :allow_destroy => true

  has_many :participants, :through => :collection_participants, :source => :pseud
  has_many :users, :through => :participants, :source => :user
  has_many :invited, :through => :collection_participants, :source => :pseud, :conditions => ['collection_participants.participant_role = ?', CollectionParticipant::INVITED]
  has_many :owners, :through => :collection_participants, :source => :pseud, :conditions => ['collection_participants.participant_role = ?', CollectionParticipant::OWNER]
  has_many :moderators, :through => :collection_participants, :source => :pseud, :conditions => ['collection_participants.participant_role = ?', CollectionParticipant::MODERATOR]
  has_many :members, :through => :collection_participants, :source => :pseud, :conditions => ['collection_participants.participant_role = ?', CollectionParticipant::MEMBER]
  has_many :posting_participants, :through => :collection_participants, :source => :pseud,
      :conditions => ['collection_participants.participant_role in (?)', [CollectionParticipant::MEMBER,CollectionParticipant::MODERATOR, CollectionParticipant::OWNER ] ]



  CHALLENGE_TYPE_OPTIONS = [
                             ["", ""],
                             [ts("Gift Exchange"), "GiftExchange"],
                             [ts("Prompt Meme"), "PromptMeme"],
                           ]

  validate :must_have_owners, :on => :save
  validate :collection_depth, :on => :save
  validate :parent_exists, :on => :save
  validate :parent_is_allowed, :on => :save

  def must_have_owners
    # we have to use collection participants because the association may not exist until after
    # the collection is saved
    errors.add(:base, ts("Collection has no valid owners.")) if (self.collection_participants + (self.parent ? self.parent.collection_participants : [])).select {|p| p.is_owner?}.empty?
  end

  def collection_depth
    if (self.parent && self.parent.parent) || (self.parent && !self.children.empty?) || (!self.children.empty? && !self.children.collect(&:children).flatten.empty?)
      errors.add(:base, ts("You cannot nest collections more than one deep."))
    end
  end

  def parent_exists
    unless parent_name.blank? || Collection.find_by_name(parent_name)
      errors.add(:base, ts("We couldn't find a collection with name %{name}.", :name => parent_name))
    end
  end

  def parent_is_allowed
    if parent && parent == self
      errors.add(:base, ts("Collections are not self-parenting."))
    elsif parent && !parent.user_is_maintainer?(User.current_user)
      errors.add(:base, ts("You don't have permission to work on a subcollection of %{name}.", :name => parent.name))
    end
  end



  validates_presence_of :name, :message => t('collection.no_name', :default => "Please enter a name for your collection.")
  validates_uniqueness_of :name, :case_sensitive => false, :message => t('collection.duplicate_name', :default => 'Sorry, that name is already taken. Try again, please!')
  validates_length_of :name,
    :minimum => ArchiveConfig.TITLE_MIN,
    :too_short=> t('title_too_short', :default => "must be at least %{min} characters long.", :min => ArchiveConfig.TITLE_MIN)
  validates_length_of :name,
    :maximum => ArchiveConfig.TITLE_MAX,
    :too_long=> t('title_too_long', :default => "must be less than %{max} characters long.", :max => ArchiveConfig.TITLE_MAX)
  validates_format_of :name,
    :message => t('collection.name_invalid', :default => 'must begin and end with a letter or number; it may also contain underscores but no other characters.'),
    :with => /\A[A-Za-z0-9]\w*[A-Za-z0-9]\Z/

  validates :email, :email_veracity => {:allow_blank => true}

  validates_presence_of :title, :message => t('collection.no_title', :default => "Please enter a title to be displayed for your collection.")
  validates_length_of :title,
    :minimum => ArchiveConfig.TITLE_MIN,
    :too_short=> t('title_too_short', :default => "must be at least %{min} characters long.", :min => ArchiveConfig.TITLE_MIN)
  validates_length_of :title,
    :maximum => ArchiveConfig.TITLE_MAX,
    :too_long=> t('title_too_long', :default => "must be less than %{max} characters long.", :max => ArchiveConfig.TITLE_MAX)
  validate :no_reserved_strings
  def no_reserved_strings
    errors.add(:title, ts("^Sorry, we've had to reserve the ',,' string for behind-the-scenes usage!")) if
      title.match(/\,\,/)
  end

  validates_length_of :description,
    :allow_blank => true,
    :maximum => ArchiveConfig.SUMMARY_MAX,
    :too_long => t('summary_too_long', :default => "must be less than %{max} characters long.", :max => ArchiveConfig.SUMMARY_MAX)

  validates_format_of :header_image_url, :allow_blank => true, :with => URI::regexp(%w(http https)), :message => t('collection.url_invalid', :default => "Not a valid URL.")
  validates_format_of :header_image_url, :allow_blank => true, :with => /\.(png|gif|jpg)$/, :message => t('collection.image_invalid', :default => "Only gif, jpg, png files allowed.")

  scope :top_level, where(:parent_id => nil)
  scope :closed, joins(:collection_preference).where("collection_preferences.closed = ?", true)
  scope :not_closed, joins(:collection_preference).where("collection_preferences.closed = ?", false)
  scope :moderated, joins(:collection_preference).where("collection_preferences.moderated = ?", true)
  scope :unmoderated, joins(:collection_preference).where("collection_preferences.moderated = ?", false)
  scope :unrevealed, joins(:collection_preference).where("collection_preferences.unrevealed = ?", true)
  scope :anonymous, joins(:collection_preference).where("collection_preferences.anonymous = ?", true)
  scope :name_only, select("collections.name")
  scope :by_title, order(:title)

  # we need to add other challenge types to this join in future
  scope :ge_signups_open, joins("INNER JOIN gift_exchanges on gift_exchanges.id = challenge_id").
                       where("gift_exchanges.signup_open = 1 && gift_exchanges.signups_close_at > ?", Time.now).
                       order("gift_exchanges.signups_close_at")
  scope :pm_signups_open, joins("INNER JOIN prompt_memes on prompt_memes.id = challenge_id").
                       where("prompt_memes.signup_open = 1 && prompt_memes.signups_close_at > ?", Time.now).
                       order("prompt_memes.signups_close_at")

  scope :with_name_like, lambda {|name|
    where("collections.name LIKE ?", '%' + name + '%').
    limit(10)
  }

  scope :with_title_like, lambda {|title|
    where("collections.title LIKE ?", '%' + title + '%')
  }

  scope :with_item_count,
    select("collections.*, count(distinct collection_items.id) as item_count").
    joins("left join collections child_collections on child_collections.parent_id = collections.id
           left join collection_items on ( (collection_items.collection_id = child_collections.id OR collection_items.collection_id = collections.id)
                                     AND collection_items.user_approval_status = 1
                                     AND collection_items.collection_approval_status = 1)").
    group("collections.id")

  def to_param
    name
  end

  # Change membership of collection(s) from a particular pseud to the orphan account
  def self.orphan(pseuds, collections, default=true)
    for pseud in pseuds
      for collection in collections
        if pseud && collection && collection.owners.include?(pseud)
          orphan_pseud = default ? User.orphan_account.default_pseud : User.orphan_account.pseuds.find_or_create_by_name(pseud.name)
          pseud.change_membership(collection, orphan_pseud)
        end
      end
    end
  end
  
  ## AUTOCOMPLETE
  # set up autocomplete and override some methods
  include AutocompleteSource
  def autocomplete_search_string
    "#{name} #{title}"
  end

  def autocomplete_prefixes
    [ "autocomplete_collection_all",
      "autocomplete_collection_#{closed? ? 'closed' : 'open'}" ]
  end

  def autocomplete_score
    all_approved_works_count + all_approved_bookmarks_count
  end
  ## END AUTOCOMPLETE

  
  def parent_name=(name)
    @parent_name = name
    self.parent = Collection.find_by_name(name)
  end

  def parent_name
    @parent_name || (self.parent ? self.parent.name : "")
  end

  def all_owners
    (self.owners + (self.parent ? self.parent.owners : [])).uniq
  end

  def all_moderators
    (self.moderators + (self.parent ? self.parent.moderators : [])).uniq
  end

  def all_members
    (self.members + (self.parent ? self.parent.members : [])).uniq
  end

  def all_posting_participants
    (self.posting_participants + (self.parent ? self.parent.posting_participants : [])).uniq
  end

  def all_participants
    (self.participants + (self.parent ? self.parent.participants : [])).uniq
  end

  def all_approved_works
    (self.approved_works + (self.children ? self.children.collect(&:approved_works).flatten : [])).uniq
  end

  def all_approved_works_count
    count = self.approved_works.count
    self.children.each {|child| count += child.approved_works.count}
    count
  end

  def all_approved_bookmarks
    (self.approved_bookmarks + (self.children ? self.children.collect(&:approved_bookmarks).flatten : [])).uniq
  end

  def all_approved_bookmarks_count
    count = self.approved_bookmarks.count
    self.children.each {|child| count += child.approved_bookmarks.count}
    count
  end

  def all_fandoms
    Fandom.for_collections([self] + self.children).select("DISTINCT tags.*")
  end

  def all_fandoms_count
    # this is the only way to get this to be done with an actual efficient count query instead of
    # actually loading the tags and then counting, because count on AR queries isn't respecting
    # the selects :P
    # see: https://rails.lighthouseapp.com/projects/8994/tickets/1334-count-calculations-should-respect-scoped-selects
    Fandom.select("count(distinct tags.id) as count").for_collections([self] + self.children).first.count
  end

  def maintainers
    self.all_owners + self.all_moderators
  end

  def user_is_owner?(user)
    user && user != :false && !(user.pseuds & self.all_owners).empty?
  end

  def user_is_moderator?(user)
    user && user != :false && !(user.pseuds & self.all_moderators).empty?
  end

  def user_is_maintainer?(user)
    user && user != :false && !(user.pseuds & (self.all_moderators + self.all_owners)).empty?
  end

  def user_is_participant?(user)
    user && user != :false && !get_participating_pseuds_for_user(user).empty?
  end

  def user_is_posting_participant?(user)
    user && user != :false && !(user.pseuds & self.all_posting_participants).empty?
  end

  def get_participating_pseuds_for_user(user)
    (user && user != :false) ? user.pseuds & self.all_participants : []
  end

  def get_participants_for_user(user)
    return [] unless user
    CollectionParticipant.in_collection(self).for_user(user)
  end

  def assignment_notification
    self.collection_profile.assignment_notification || (parent ? parent.collection_profile.assignment_notification : "")
  end

  def gift_notification
    self.collection_profile.gift_notification || (parent ? parent.collection_profile.gift_notification : "")
  end

  def moderated? ; self.collection_preference.moderated ; end
  def closed? ; self.collection_preference.closed ; end
  def unrevealed? ; self.collection_preference.unrevealed ; end
  def anonymous? ; self.collection_preference.anonymous ; end
  def challenge? ; !self.challenge.nil? ; end
  def gift_exchange?
    if self.challenge_type == "GiftExchange"
      return true
    end
  end
  def prompt_meme?
    if self.challenge_type == "PromptMeme"
      return true
    end
  end

  def not_empty?
    self.all_approved_works.count > 0 || self.children.count > 0 || self.all_approved_bookmarks.count > 0
  end

  def get_maintainers_email
    return self.email if !self.email.blank?
    return parent.email if parent && !parent.email.blank?
    "#{self.maintainers.collect(&:user).flatten.uniq.collect(&:email).join(',')}"
  end

  def notify_maintainers(subject, message)
    # send maintainers a notice via email
    UserMailer.collection_notification(self.id, subject, message).deliver
  end
  
  @queue = :collection
  # This will be called by a worker when a job needs to be processed
  def self.perform(id, method, *args)
    find(id).send(method, *args)
  end

  # We can pass this any Collection instance method that we want to
  # run later.
  def async(method, *args)
    Resque.enqueue(Collection, id, method, *args)
  end
  
  def reveal!
    approved_collection_items.update_all("unrevealed = 0")
    async(:send_reveal_notifications)
  end

  def reveal_authors!
    approved_collection_items.update_all("anonymous = 0")
    async(:send_author_reveal_notifications)
  end
  
  def send_reveal_notifications
    approved_collection_items.each {|collection_item| collection_item.notify_of_reveal}
  end
  
  def send_author_reveal_notifications
    approved_collection_items.each {|collection_item| collection_item.notify_of_author_reveal}
  end

  def self.sorted_and_filtered(sort, filters, page)
    pagination_args = {:page => page}

    # build up the query with scopes based on the options the user specifies
    query = Collection.top_level
    
    if !filters[:title].blank?
      # we get the matching collections out of autocomplete and use their ids
      ids = Collection.autocomplete_lookup(filters[:title], 
                filters[:closed].blank? ? "autocomplete_collection_all" : (filters[:closed] ? "autocomplete_collection_closed" : "autocomplete_collection_open")
             ).map {|result| Collection.id_from_autocomplete(result)}
      query = query.where("collections.id in (?)", ids)
    else
      query = (filters[:closed] == "true" ? query.closed : query.not_closed) if !filters[:closed].blank?
    end
    query = (filters[:moderated] == "true" ? query.moderated : query.unmoderated) if !filters[:moderated].blank?
    if sort.match /item_count/
      query = query.with_item_count
      pagination_args.merge!({:order => sort})
    else
      query = query.order(sort)
    end

    if !filters[:fandom].blank?
      fandom = Fandom.find_by_name(filters[:fandom])
      if fandom
        (fandom.approved_collections & query).paginate(pagination_args)
      else
        []
      end
    else
      query.paginate(pagination_args)
    end
  end

end
