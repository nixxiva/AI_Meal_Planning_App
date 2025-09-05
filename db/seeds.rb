# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb

# Step 1: Gumawa o hanapin ang isang User record.
# Kailangan natin ng user para i-attach ang mga health goals.
# db/seeds.rb

# Listahan ng mga predefined na health goals.
# health_goals_list = ['Muscle Gain', 'Fat Loss', 'Weight Maintenance', 'Increase Stamina', 'Improve Flexibility', 'Boost Endurance', 'Cardio Health']

# health_goals_list.each do |goal_name|
#   HealthGoal.find_or_create_by!(goal_name: goal_name)
# end

# puts "Seeded default health goals: #{HealthGoal.all.pluck(:goal_name).join(', ')}"

health_goals_data = [
  { id: 1, goal_name: 'Muscle Gain' },
  { id: 2, goal_name: 'Fat Loss' },
  { id: 3, goal_name: 'Weight Maintenance' },
  { id: 4, goal_name: 'Increase Stamina' },
  { id: 5, goal_name: 'Improve Flexibility' },
  { id: 6, goal_name: 'Boost Endurance' },
  { id: 7, goal_name: 'Cardio Health' }
]

health_goals_data.each do |goal|
  # Using find_or_create_by to ensure records are not duplicated on subsequent runs
  HealthGoal.find_or_create_by!(id: goal[:id]) do |h|
    h.goal_name = goal[:goal_name]
  end
end

puts "Seeded default health goals: #{HealthGoal.all.pluck(:goal_name).join(', ')}"