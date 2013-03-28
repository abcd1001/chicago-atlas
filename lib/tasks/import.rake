namespace :db do
  namespace :import do

    desc "Fetch and import all Health Atlas Data"
    task :all => :environment do
      Rake::Task["db:import:community_areas"].invoke
      Rake::Task["db:import:chicago_dph"].invoke
      Rake::Task["db:import:chicago_health_facilities"].invoke
    end
    
    desc "Fetch Chicago Community Areas from the TribApps Boundary Service"
    task :community_areas => :environment do
      require 'open-uri'
      require 'json'
      Geography.delete_all

      community_area_endpoints = JSON.parse(open("http://api.boundaries.tribapps.com/1.0/boundary-set/community-areas/").read)['boundaries']
      community_area_endpoints.each do |endpoint|
        area_json = JSON.parse(open("http://api.boundaries.tribapps.com/#{endpoint}").read)

        area = Geography.new(
          :geo_type => area_json['kind'],
          :name => area_json['name'],
          :slug => area_json['name'].parameterize.underscore.to_sym,
          :geometry => ActiveSupport::JSON.encode(area_json['simple_shape']),
          :centroid => ActiveSupport::JSON.encode(area_json['centroid']['coordinates'])
        )
        area.id = area_json['external_id']
        puts "importing #{area.name}"
        area.save!
      end

      puts 'Done!'
    end

    desc "Fetch CDPH datasets from the Chicago Data Portal and import to database"
    task :chicago_dph => :environment do
      require 'csv' 

      Dataset.where(:provider => "Chicago Department of Public Health").each do |d|
        Statistic.delete_all("dataset_id = #{d.id}")
        d.delete
      end

      datasets = [
        # Births
        {:category => 'Births', :name => 'Birth Rate', :parse_tokens => ['birth_rate'], :socrata_id => '4arr-givg', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Births-and-birth-rates-in/4arr-givg', :description => "Crude birth rate (births per 1,000 residents) with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,12.0,18.0,24]"},
        {:category => 'Births', :name => 'Fertility Rate', :parse_tokens => ['fertility_rate'], :socrata_id => 'g5zk-9ycw', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-General-fertility-rates-i/g5zk-9ycw', :description => "Annual general fertility rate (births per 1,000 females aged 15-44 years) with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,60,80,100]"},
        {:category => 'Births', :name => 'Percent of Low Weight Births', :parse_tokens => ['percent'], :socrata_id => 'fbxr-9u99', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Low-birth-weight-in-Chica/fbxr-9u99', :description => "Percent of total births that were low birth weight with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,7.50,12.50,17.50]"},
        {:category => 'Births', :name => 'Percent of Preterm Births', :parse_tokens => ['percent'], :socrata_id => 'rhy3-4x2f', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Preterm-births-in-Chicago/rhy3-4x2f', :description => "Percent of total births these preterm births represent, with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,10,14,18]"},
        {:category => 'Births', :name => 'Teen Birth Rate', :parse_tokens => ['teen_birth_rate'], :socrata_id => '9kva-bt6k', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Births-to-mothers-aged-15/9kva-bt6k', :description => "Annual birth rate (births per 1,000 females aged 15-19 years) with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,40.0,80.0,120]"},

        # special case: blown up rows for 1ST TRIMESTER, 2ND TRIMESTER, 3RD TRIMESTER, NO PRENATAL CARE, NOT GIVEN
        {:category => 'Births', :name => 'Prenatal Care Obtained in 1st Trimester', :group_column => 'trimester_prenatal_care_began', :groups => ['1ST TRIMESTER'], :parse_tokens => ['percent'], :socrata_id => '2q9j-hh6g', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Prenatal-care-in-Chicago-/2q9j-hh6g', :description => "Percent of live births in which the mother began prenatal care during the 1st trimester with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2009.", :choropleth_cutoffs => "[0,65,73,81]"},
        
        # Deaths
        {:category => 'Deaths', :name => 'Infant Mortality Rate', :parse_tokens => ['deaths'], :socrata_id => 'bfhr-4ckq', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Infant-mortality-in-Chica/bfhr-4ckq', :description => "Annual number of infant deaths, by Chicago community area, for the years 2004 - 2008."},

        # special case: broken down by death cause
        # causes: All causes in females,All causes in males,Alzheimers disease,Assault (homicide),Breast cancer in females,Cancer (all sites),Colorectal cancer,Coronary heart disease,Diabetes-related,Firearm-related,Injury, unintentional,Kidney disease (nephritis, nephrotic syndrome and nephrosis),Liver disease and cirrhosis,Lung cancer,Prostate cancer in males,Stroke (cerebrovascular disease),Suicide (intentional self-harm)
        # {:category => 'Deaths', :name => 'Mortality', :parse_tokens => [], :socrata_id => 'j6cj-r444', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Selected-underlying-cause/j6cj-r444'},
      
        # Environmental Health
        {:category => 'Environmental Health', :name => 'Lead Screening Rate', :parse_tokens => ['lead_screening_rate'], :socrata_id => 'v2z5-jyrq', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Screening-for-elevated-bl/v2z5-jyrq', :description => "Estimated rate per 1,000 children aged 0-6 years receiving a blood lead level test, by Chicago community area, for the years 1999 - 2011."},
        {:category => 'Environmental Health', :name => 'Elevated Blood Lead Levels', :parse_tokens => ['percent_elevated'], :socrata_id => 'v2z5-jyrq', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Screening-for-elevated-bl/v2z5-jyrq', :description => "Estimated percentage of children aged 0-6 years tested found to have an elevated blood lead level with corresponding 95% confidence intervals, by Chicago community area, for the years 1999 - 2011."},
        
        # Infectious disease
        {:category => 'Infectious disease', :name => 'Tuberculosis', :parse_tokens => ['cases'], :socrata_id => 'ndk3-zftj', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Tuberculosis-cases-and-av/ndk3-zftj', :description => "Annual number of new cases of tuberculosis by Chicago community area, for the years 2007 - 2011.", :choropleth_cutoffs => "[0,4.0,8.0,12]"},
        {:category => 'Infectious disease', :name => 'Gonorrhea in females', :parse_tokens => ['incidence_rate'], :socrata_id => 'cgjw-mn43', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Gonorrhea-cases-for-femal/cgjw-mn43', :description => "Annual number of newly reported, laboratory-confirmed cases of gonorrhea (Neisseria gonorrhoeae) among females aged 15-44 years and annual gonorrhea incidence rate (cases per 100,000 females aged 15-44 years) with corresponding 95% confidence intervals by Chicago community area, for years 2000 - 2011.", :choropleth_cutoffs => "[0,600,1200,1800]"},

        # TODO: accomodate 'Cases 2000 Male 15-44'
        {:category => 'Infectious disease', :name => 'Gonorrhea in males', :parse_tokens => ['incidence_rate'], :socrata_id => 'm5qn-gmjx', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-health-statistics-Gonorrhea-cases-for-males/m5qn-gmjx', :description => "Annual number of newly reported, laboratory-confirmed cases of gonorrhea (Neisseria gonorrhoeae) among males aged 15-44 years and annual gonorrhea incidence rate (cases per 100,000 males aged 15-44 years) with corresponding 95% confidence intervals by Chicago community area, for years 2000 - 2011. ", :choropleth_cutoffs => "[0,600,1200,1800]"},

        # TODO: accomodate 'Cases 2000 Female 15-44'
        {:category => 'Infectious disease', :name => 'Chlamydia in females', :parse_tokens => ['incidence_rate'], :socrata_id => 'bz6k-73ti', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Chlamydia-cases-among-fem/bz6k-73ti', :description => "Annual number of newly reported, laboratory-confirmed cases of chlamydia (Chlamydia trachomatis) among females aged 15-44 years and annual chlamydia incidence rate (cases per 100,000 females aged 15-44 years) with corresponding 95% confidence intervals by Chicago community area, for years 2000 - 2011. "},

        # Chronic disease
        # these are aggregated by zip code
        # {:category => 'Chronic disease', :name => 'Diabetes Hospitalizations', :parse_tokens => ['Hospitalizations', 'Crude Rate', 'Adjusted Rate'], :socrata_id => 'vekt-28b5', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Diabetes-hospitalizations/vekt-28b5'},
        # {:category => 'Chronic disease', :name => 'Diabetes Hospitalizations', :parse_tokens => ['Hospitalizations', 'Crude Rate', 'Adjusted Rate'], :socrata_id => 'vazh-t57q', :url => 'https://data.cityofchicago.org/Health-Human-Services/Public-Health-Statistics-Asthma-hospitalizations-i/vazh-t57q'},
      ]

      datasets.each do |d|
        handle = d[:name].parameterize.underscore.to_sym
        
        puts "downloading '#{d[:name]}'"
        sh "curl -o tmp/#{handle}.csv https://data.cityofchicago.org/api/views/#{d[:socrata_id]}/rows.csv?accessType=DOWNLOAD"
      
        csv_text = File.read("tmp/#{handle}.csv")
        csv = CSV.parse(csv_text, {:headers => true, :header_converters => :symbol})

        puts csv.first.inspect

        d[:parse_tokens].each do |parse_token|

          if d.has_key?(:group_column) and d.has_key?(:groups)
            puts "unpacking groups based on '#{d[:group_column]}' column"
            d[:groups].each do |group|
              # save each data portal set, parse_token and group combination as a separate dataset
              dataset = save_cdph_dataset(d, parse_token, handle, group)

              csv.each do |row|
                process_cdph_row(row, dataset, parse_token, d[:group_column], group)
              end

              stat_count = Statistic.count(:conditions => "dataset_id = #{dataset.id}")
              puts "#{parse_token}, #{group}: imported #{stat_count} statistics"
            end
          else
            # save each data portal set and parse_token combination as a separate dataset
            dataset = save_cdph_dataset(d, parse_token, handle)

            csv.each do |row|
              process_cdph_row(row, dataset, parse_token)
            end

            stat_count = Statistic.count(:conditions => "dataset_id = #{dataset.id}")
            puts "#{parse_token}: imported #{stat_count} statistics"
          end
        end
      end
      puts 'Done!'
    end

    def save_cdph_dataset(d, parse_token, handle, group='')

      dataset = Dataset.new(
        :name => d[:name],
        :slug => "#{handle}",
        :description => '', # leaving blank for now
        :provider => 'Chicago Department of Public Health',
        :url => d[:url],
        :category_id => Category.where(:name => d[:category]).first.id,
        :data_type => 'condition',
        :description => d[:description]
      )

      if (d.has_key?(:choropleth_cutoffs))
        dataset.choropleth_cutoffs = d[:choropleth_cutoffs]
      end

      dataset.save!
      dataset
    end

    def process_cdph_row(row, dataset, parse_token, group_column='', group='')
      row = row.to_hash.with_indifferent_access

      # sometimes Community Area is named differently
      community_area = row['community_area']
      if community_area.nil? || community_area == ''
        community_area = row['community_area_number']
      end

      # special case for Chicago - given an ID of 0, 88 or 100 by CDPH
      if community_area == '0' or community_area == '88'
        community_area = '100' # Chicago is manually imported, see seeds.rb
      end

      if group != '' and group_column != ''
        if row[group_column] == group
          save_cdph_statistic(row, dataset, community_area, parse_token)
        end
      else
        save_cdph_statistic(row, dataset, community_area, parse_token)
      end
    end

    def save_cdph_statistic(row, dataset, community_area, parse_token)
      (1999..Time.now.year).each do |year|
        if (row.has_key?("#{parse_token}_#{year}"))
          stat = Statistic.new(
            :dataset_id => dataset.id,
            :geography_id => community_area,
            :year => year,
            :name => parse_token, 
            :value => row["#{parse_token}_#{year}"]
          )

          if (row.has_key?("#{parse_token}_#{year}_lower_ci"))
            stat.lower_ci = row["#{parse_token}_#{year}_lower_ci"]
          elsif (row.has_key?("#{parse_token}_#{year}_lower"))
            stat.lower_ci = row["#{parse_token}_#{year}_lower"]
          end

          if (row.has_key?("#{parse_token}_#{year}_upper_ci"))
            stat.upper_ci = row["#{parse_token}_#{year}_upper_ci"]
          elsif (row.has_key?("#{parse_token}_#{year}_upper"))
            stat.upper_ci = row["#{parse_token}_#{year}_upper"]
          end

          stat.save!
        end

      end
    end

    desc "Fetch Metro Chicago Health Facilities"
    task :chicago_health_facilities => :environment do
      require 'csv' 

      Dataset.where(:provider => "Metro Chicago Data").each do |d|
        InterventionLocation.delete_all("dataset_id = #{d.id}")
        d.delete
      end

      datasets = [{:name => 'Metro Chicago Health Facilities', :socrata_id => 'kt59-57by', :url => 'https://www.metrochicagodata.org/dataset/Metro-Chicago-Health-Facilities/kt59-57by'}]

      datasets.each do |d|
        handle = d[:name].parameterize.underscore.to_sym

        # puts "downloading '#{d[:name]}'"
        # sh "curl -o tmp/#{handle}.csv https://www.metrochicagodata.org/api/views/#{d[:socrata_id]}/rows.csv?accessType=DOWNLOAD"
        
        csv_text = File.read("db/import/#{handle}.csv")
        csv = CSV.parse(csv_text, :headers => true)

        puts csv.first.inspect

        dataset = Dataset.new(
          :name => d[:name],
          :slug => handle,
          :description => '', # leaving blank for now
          :provider => 'Metro Chicago Data',
          :url => d[:url],
          # :category_id => Category.where(:name => d[:category]).first.id,
          :data_type => 'intervention'
        )
        dataset.save!
        dataset

        csv.each do |row|
          # regex to pluck out the lat/long from the LOCATION column
          matches = /([^\-]*)\((\-?\d+\.\d+?),\s*(\-?\d+\.\d+?)\)/.match(row["LOCATION"])
          # puts matches.inspect
          if not matches.nil? and matches[1].downcase.include? "chicago"
            address = matches[1].gsub('\n', '')
            latitude = matches[2]
            longitude = matches[3]

            intervention = InterventionLocation.new(
              :name => row["SITE NAME"],
              :hours => row["HOURS"],
              :phone => row["PHONE"],
              :address => address,
              :latitude => latitude,
              :longitude => longitude,
              :dataset_id => dataset.id
            )
            intervention.save!
            intervention
          end
        end

        stat_count = InterventionLocation.count(:conditions => "dataset_id = #{dataset.id}")
        puts "imported #{stat_count} intervention locations"

      end
    end


  end
end