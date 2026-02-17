# =============================================================================
# SketchUp Utility - Print All Attribute Dictionaries and Their Contents
# =============================================================================
#
# FILE       :  SketchUp_Debug_PrintAllDictionaries.rb
# PURPOSE    :  Iterates through all attribute dictionaries in the current model
#               and prints their keys and values to the Ruby Console.
# AUTHOR     :  Adam Noble (For Debugging Use in Development)
# VERSION    :  1.0.1
# CREATED    :  22-May-2025
# =============================================================================

model = Sketchup.active_model
dicts = model.attribute_dictionaries

if dicts.nil?
    puts "No attribute dictionaries found in this model."
else
    puts "Attribute Dictionaries Found:"
    puts "----------------------------------------"

    dicts.each do |dict|
        puts "Dictionary Name: #{dict.name}"
        puts "----------------------------------------"

        dict.each_pair do |key, value|
            puts "  #{key.inspect} => #{value.inspect}"
        end

        puts "\n"
    end
end
