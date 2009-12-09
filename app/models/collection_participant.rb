class CollectionParticipant < ActiveRecord::Base
  belongs_to :pseud
  has_one :user, :through => :pseud
  belongs_to :collection
  
  PARTICIPANT_ROLES = ["None", "Owner", "Moderator", "Member"]
  NONE = PARTICIPANT_ROLES[0]
  OWNER = PARTICIPANT_ROLES[1]
  MODERATOR = PARTICIPANT_ROLES[2]
  MEMBER = PARTICIPANT_ROLES[3]
  PARTICIPANT_ROLE_OPTIONS = [ [t('collection_participant.none', :default => "None"), NONE],
                         [t('collection_participant.member', :default => "Member"), MEMBER],
                         [t('collection_participant.moderator', :default => "Moderator"), MODERATOR],
                         [t('collection_participant.owner', :default => "Owner"), OWNER] ]
  
  validates_uniqueness_of :pseud_id, :scope => [:collection_id], 
    :message => t('collection_participant.not_unique', :default => "That person appears to already be a participant in that collection.")
  
  validates_presence_of :participant_role
  validates_inclusion_of :participant_role, :in => PARTICIPANT_ROLES,
    :message => t('collection.item.invalid_type', :default => "That is not a valid participant role.")

  def is_owner? ; self.participant_role == OWNER ; end
  def is_moderator? ; self.participant_role == MODERATOR ; end
  def is_maintainer? ; is_owner? || is_moderator? ; end
  def is_member? ; self.participant_role == MEMBER ; end

  def approve_membership!
    self.participant_role = MEMBER
    save
  end

  def user_allowed_to_destroy?(user)
    self.collection.user_is_maintainer?(user) || self.pseud.user == user
  end
  
  def user_allowed_to_promote?(user, role)
    (role == MEMBER || role == NONE) ? self.collection.user_is_maintainer?(user) : self.collection.user_is_owner?(user)
  end

end
