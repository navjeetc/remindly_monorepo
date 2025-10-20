FactoryBot.define do
  factory :task do
    association :senior, factory: :user, role: :senior
    association :created_by, factory: :user, role: :caregiver
    
    title { "Doctor Appointment" }
    description { "Annual checkup with Dr. Smith" }
    task_type { :appointment }
    status { :pending }
    priority { :medium }
    scheduled_at { 1.day.from_now }
    duration_minutes { 60 }
    location { "Main St Clinic" }
    notes { "Bring insurance card" }

    trait :assigned do
      association :assigned_to, factory: :user, role: :caregiver
      status { :assigned }
    end

    trait :in_progress do
      association :assigned_to, factory: :user, role: :caregiver
      status { :in_progress }
    end

    trait :completed do
      association :assigned_to, factory: :user, role: :caregiver
      status { :completed }
      completed_at { Time.current }
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent do
      priority { :urgent }
    end

    trait :errand do
      task_type { :errand }
      title { "Grocery Shopping" }
      description { "Weekly groceries" }
    end
  end
end
