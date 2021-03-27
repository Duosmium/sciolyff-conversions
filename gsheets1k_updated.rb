#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts the CSV Output from the Google Sheets Input Template to SciolyFF

require 'csv'
require 'date'
require 'yaml'

if ARGV.empty?
  puts 'needs a file to convert'
  exit 1
end

csv = CSV.read(ARGV.last)

tournament = {}
tournament['name']     = csv.first[0] unless csv.first[0].nil?
tournament['short name']     = csv.first[1] unless csv.first[1].nil?
tournament['location'] = csv.first[2]
tournament['state']    = csv.first[3]
tournament['level']    = csv.first[4]
tournament['division'] = csv.first[5]
tournament['year']     = csv.first[6].to_i
tournament['date']     = Date.parse(csv.first[7]) unless csv.first[7].nil?
tournament['start date']     = Date.parse(csv.first[8]) unless csv.first[8].nil?
tournament['end date']     = Date.parse(csv.first[9]) unless csv.first[9].nil?
tournament['awards date']     = Date.parse(csv.first[10]) unless csv.first[10].nil?
tournament['medals'] = csv.first[11].to_i unless csv.first[11].nil?
tournament['trophies'] = csv.first[12].to_i unless csv.first[12].nil?
tournament['bids'] = = csv.first[13].to_i unless csv.first[13].nil?
tournament['n offset'] = csv.first[14].to_i unless csv.first[14].nil?

events =
  csv[1].map.with_index do |event_name, i|
    event = {}
    event['name']    = event_name
    event['trial']   = true if csv[2][i] == 'Trial'
    event['trialed'] = true if csv[2][i] == 'Trialed'
    event
  end

teams =
  csv[3..1002].take_while { |row| !row.first.nil? }.map do |row|
    team = {}
    team['number']              = row[0].to_i
    team['school']              = row[1]
    team['school abbreviation'] = row[2]
    team['suffix']              = row[3]
    team['city']                = row[4]
    team['state']               = row[5]
    team['track']         = row[6]
    team['exhibition']          = true if row[7] == 'Yes'
    team['penalty points']      = row[8] # will be converted to penalty later
    team.reject { |_, v| v.nil? }
  end

placings =
  teams.map.with_index do |team, t_i|
    events.map.with_index do |event, e_i|
      placing = {}
      placing['team']  = team['number']
      placing['event'] = event['name']

      raw_place = csv[1003..2002][t_i][e_i]
      case raw_place.upcase
      when 'PO' then placing['participated'] = true # not strictly needed
      when 'NS' then placing['participated'] = false
      when 'DQ' then placing['disqualified'] = true
      when 'LP' then placing['unknown']      = true
      when '??' then placing['unknown']      = true
      when 'EX' then placing['exempt']       = true; placing['participated'] = false

      when /EX\[(.+)\]/
        placing['exempt'] = true
        case $1
        when 'PO' then placing['participated'] = true
        when 'DQ' then placing['disqualified'] = true
        when 'LP' then placing['low place']    = true
        else           placing['place'] = $1.to_i
        end

      else           placing['place']        = raw_place.to_i
      end
      placing
    end
  end.flatten

penalties =
  teams.map do |team|
    penalty = {}
    points = team.delete('penalty points')
    next if points.nil?

    penalty['team']   = team['number']
    penalty['points'] = points.to_i
    penalty
  end.compact

# Identify and fix placings that are just participations points
events.map { |e| e['name'] }.each do |event_name|
  last_place_placings = placings.select do |p|
    p['event'] == event_name &&
      p['place'] == teams.count
  end
  next if placings.find do |p|
            p['event'] == event_name && p['place'] == (teams.count - 1)
          end

  last_place_placings.each do |placing|
    placing.store('participated', true)
    placing.delete('place')
  end
end

# shift placings down for exhibition teams (fixes fake ties)
# does not work if there are actual ties in placings
if ARGV.include?('--exhibition') || ARGV.include?('-e')

  def compare(p1, p2, teams)
    p1_ex = teams.find {|t| t['number'] == p1['team'] }['exhibition']
    p2_ex = teams.find {|t| t['number'] == p2['team'] }['exhibition']

    if p1['place'] != p2['place'] then p1['place'] <=> p2['place']
    elsif   p1_ex        && !p2_ex        then -1
    elsif  !p1_ex        &&  p2_ex        then  1
    elsif   p1['exempt'] && !p2['exempt'] then -1
    elsif  !p1['exempt'] &&  p2['exempt'] then  1
    else
      raise "Unresolved tie for #{p1['event']} at #{p1['place']}"
    end
  end

  non_place_placings = placings.reject { |p| p['place'] }

  placings = placings
    .select { |p| p['place'] }
    .group_by { |p| p['event'] }
    .values
    .map do |p_arr|
    p_arr
      .sort { |p1, p2| compare(p1, p2, teams) }
      .each_with_index.map { |p, i| p['place'] = i + 1; p }
  end
    .flatten
    .concat(non_place_placings)
end

# automatically mark ties (make sure to check for PO/NS/DQ first!)
if ARGV.include?('--mark-ties') || ARGV.include?('-t')
  placings = placings.map do |p|
    p['tie'] = true if placings.find do |other_p|
      other_p['place'] &&
        other_p['place'] == p['place'] &&
        other_p['event'] == p['event'] &&
        other_p != p
    end
    p
  end
end

rep = {}
rep['Tournament'] = tournament
rep['Events']     = events
rep['Teams']      = teams
rep['Placings']   = placings
rep['Penalties']  = penalties unless penalties.empty?


output_file = ARGV.last.split('.').first + '.yaml'
File.open(output_file, 'w') { |f| f.write(YAML.dump(rep)) }
system("sciolyff #{output_file}")
