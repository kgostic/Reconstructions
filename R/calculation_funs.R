
get_p_infection_year = function(birth_year,
                                observation_year, ## Year of data collection, which matters if observation_year is shortly after birth_year
                                baseline_annual_p_infection = 0.28, ## Baseline annual probability of infection
                                max_year){ ## max calendar year for which to output estimates
  ## Function to calculate probs of first exposure in year x, given birth in year y
  ## INPUTS
  ##    - year in which an individual was born (birth.year)
  ##    - year in which the individual became infected with bird flu (infection year)
  ## OUTPUTS
  ##    - vector of 13 probabilities, the first representing the probability of first flu infection in the first year of life (age 0), the second representing the probability of first flu infection in the second year of life (age 1), and so on up to the 13th year of life (age 12)
  stopifnot(observation_year <= max_year)
  cat('Reading annual intensities from ../processed_data/Intensitymaster.csv. See Gostic et al. 2016 for details.')
  intensity_df = read_csv('../processed-data/Intensitymatser.csv', show_col_types = F)
  # Weighted attack rate = annual prob infection weighted by circulation intensity
  weighted.attack.rate = baseline_annual_p_infection*(intensity_df$intensity)
  names(weighted.attack.rate) = intensity_df$year
  ################# Calculations ---------------
  possible_imprinting_years = birth_year:min(birth_year+12, observation_year) #Calendar years of first infection (ages 0-12)
  nn = length(possible_imprinting_years) # How many possible years of first infection? (should be 13)
  valid_attack_rates = weighted.attack.rate[as.character(possible_imprinting_years)] #Get weighted attack rates corresponding to possible years of first infection
  attack_rate_complements = matrix(rep(1-valid_attack_rates, nn), nn, nn, byrow = T)
  ## Create matrices of 0s and 1s, which will be used below to vectorize and speed calculations
  infection_year = not_infection_year = matrix(0, nn, nn)
  diag(infection_year) = 1   #Fill in diagonal of one with 1s for years of first infection
  not_infection_year[lower.tri(not_infection_year)] = 1  #Fill in sub-diagonal for all the years since birth in which the individual escaped infection. 
  # Exact probability of escaping infection in the previous (x-1) years, and becoming infected in year x
  prod.mat = (valid_attack_rates*infection_year)+(attack_rate_complements*not_infection_year)
  #Fill in upper triangle with 1s to make multiplication possible
  prod.mat[upper.tri(prod.mat)] = 1
  #Take product across rows
  p_ij = apply(prod.mat, 1, prod)
  p_ij # Output probability of first infection in year i given birth year
}



get_imprinting_probabilities <- function(observation_years,  ## Year of data collection, which matters if observation_year is shortly after birth_year
                                         countries ## vector of one or more country names. See available_countries() for help.
){
  ## This is the master function
  ## INPUT - a vector of countries, a vector of observation years
  ## OUTPUT - a list of matrices containing subtype-specific imprinting probabilities for each country-year of observation, and each birth year
  max_year = max(observation_years)
  stopifnot(max_year <= as.numeric(format(Sys.Date(), '%Y')))
  birth_years = 1918:max_year
  infection_years = birth_years
  nn_birth_years = length(birth_years)
  
  #Initialize matrices to store imprinting probabilities for each country and year
  #Rows - which country and year are we doing the reconstruction from the persepctive of?
  #Cols - what birth year are we estimating imprinting probabilities for?
  H1N1_probs = matrix(NA, 
                      nrow = length(countries)*length(observation_years), 
                      ncol = length(birth_years), 
                      dimnames = list(paste(rep(observation_years, length(countries)), rep(countries, each = length(observation_years)), sep = ''), rev(birth_years))) 
  H2N2_probs = naive_probs = H3N2_probs = H1N1_probs
  
  ## For each country, get imprinting probabilities
  for(this_country in countries){
    who_region = get_WHO_region(this_country)
    this_epi_data = get_country_data(this_country, max_year)
    
    #Extract and data from birth years of interest
    #These describe the fraction of circulating influenza viruses isolated in a given year that were of subtype H1N1 (type1), H2N2 (type2), or H3N2 (type3)
    H1.frac = as.numeric(this_epi_data['A/H1N1', as.character(birth_years)]) 
    H2.frac = as.numeric(this_epi_data['A/H2N2', as.character(birth_years)]) 
    H3.frac = as.numeric(this_epi_data['A/H3N2', as.character(birth_years)]) 
    names(H1.frac) = names(H2.frac) = names(H3.frac) = as.character(birth_years)
    
    ## Initialize master matrix with observation_years on rows and birth years on columns
    country_H1_mat = matrix(0, 
                            nrow = length(observation_years), 
                            ncol = length(birth_years), 
                            dimnames = list((observation_years), (birth_years)))
    country_naive_mat = country_H2_mat = country_H3_mat = country_H1_mat
    
    ## Loop across observation years
    for(jj in 1:length(observation_years)){
      ## Loop across birth years
      n_valid_birth_years = observation_years[jj]-1918+1
      for(ii in 1:n_valid_birth_years){ #for all birth years elapsed up to the observation year
        n_infection_years = min(12, observation_years[jj]-birth_years[ii]) # first infections can occur up to age 12, or up until the current year, whichever comes first
        inf.probs = get_p_infection_year(birth_years[ii], observation_years[jj], 
                                         baseline_annual_p_infection = 0.28, max_year) # Get vector of year-specific probs of first infection
        #If all 13 possible years of infection have passed, normalize so that the probability of imprinting from age 0-12 sums to 1
        if(length(inf.probs) == 13) inf.probs = inf.probs/sum(inf.probs)
        # Else, don't normalize and extract the probability of remaiing naive below.
        
        #Fill in the appropriate row (observation year) and column (birth year) of the output matrix
        #The overall probabilty of imprinting to a specific subtype for a given birth year is the dot product of year-specific probabilities of any imprinting, and the year-specific fraction of seasonal circulation caused by the subtype of interest
        valid_infection_years = as.character(birth_years[ii:(ii+n_infection_years)])
        country_H1_mat[jj, ii] = sum(inf.probs*H1.frac[valid_infection_years])
        country_H2_mat[jj, ii] = sum(inf.probs*H2.frac[valid_infection_years])
        country_H3_mat[jj, ii] = sum(inf.probs*H3.frac[valid_infection_years])
        country_naive_mat[jj, ii] = round(1-sum(inf.probs), digits = 8) # Rounds to the nearest 8 to avoid machine 0 errors
      } ## Close loop over valid birth years
    } ## Close loop over observation years
    
    #return the output in order of current_year:1918
    descending_chronological_order = as.character(max(birth_years):min(birth_years))
    country_H1_mat = country_H1_mat[,descending_chronological_order]
    country_H2_mat = country_H2_mat[,descending_chronological_order]
    country_H3_mat = country_H3_mat[,descending_chronological_order]
    country_naive_mat = country_naive_mat[,descending_chronological_order]
    
    ##  Fill in the master matrix with country-specific outputs
    cc = which(countries == this_country)
    rows_for_this_country = ((cc-1)*length(observation_years))+1:length(observation_years)
    H1N1_probs[rows_for_this_country, ] = country_H1_mat 
    H2N2_probs[rows_for_this_country, ] = country_H2_mat
    H3N2_probs[rows_for_this_country, ] = country_H3_mat
    naive_probs[rows_for_this_country, ] = country_naive_mat
  } ## Close loop across countries
  
  ## Check that the total for each birth year is 1 when rounded to 4 decimals
  total = H1N1_probs+H2N2_probs+H3N2_probs+naive_probs
  if(any(! (round(total, 4)%in%c(0,1)) )){warning('Weights do not sum to 1')}
  
  ## Normalize so that sum of weights is exactly 1 in each birth year
  total[which(total==0)] = 1 # Reset 0 values so as not to divide by 0
  H1N1_probs = H1N1_probs/(total)
  H2N2_probs = H2N2_probs/(total)
  H3N2_probs = H3N2_probs/(total)
  naive_probs = naive_probs/(total)
  
  return(list(H1N1_probs = H1N1_probs, 
              H2N2_probs=H2N2_probs, 
              H3N2_probs=H3N2_probs, 
              naive_probs=naive_probs))
}
  



