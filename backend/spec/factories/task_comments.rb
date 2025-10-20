FactoryBot.define do
  factory :task_comment do
    association :task
    association :user, factory: :user, role: :caregiver
    
    content { "This is a comment on the task" }

    trait :long_comment do
      content { "This is a much longer comment with more details about the task and what needs to be done. It includes specific instructions and important notes." }
    end
  end
end
