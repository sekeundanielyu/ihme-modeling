"""
Purpose: Recalculates data in the cancer prep process to remove subtotals where possible
"""

import pandas as pd
import platform, sys, time

print 'Preparing data...'

#Set Directories
if platform.system() == 'Linux':
    j = "/home/j"
elif platform.system() == 'Windows':
    j = "J:"

# assign data location and data type. accept arguments if they are sent.
if len(sys.argv) < 3:
    temp_folder = 'J:/temp/registry/cancer/01_inputs/subtotal_disagg/CI5/ci5_plus_summary_inc'
    data_type = 'inc'
    data_folder = temp_folder + '/temp_' + data_type
    negative_data_ok = 1
else:
    data_folder = sys.argv[1]
    data_type = sys.argv[2]
    negative_data_ok = sys.argv[3]

# Define pathways
code_folder = j + '/WORK/07_registry/cancer/01_inputs/programs/subtotal_disaggregation'
exception_location = code_folder + '/data/subcause_issue.txt'

## #########################
## Define Functions
## ##########################
def set_subcauses(test_data):
    print "setting subcauses..."
    for c in test_data:
        test_data[c]['subcauses_remaining'] = []
        if not len(test_data[c]['codes']) or not len(test_data[c]['subcodes']): continue
        # Check if any c2 is a subcause of c. 
        for c2 in test_data:
            if c2 == c or not len(test_data[c2]['codes']) : continue
            ## Add c2 if it has not already been removed from c
            if set(test_data[c2]['codes']) <= set(test_data[c]['subcodes']) and not any(x in test_data[c]['codes_removed'] for x in test_data[c2]['codes']):
                test_data[c]['subcauses_remaining'].append(c2) 
                ## If the added single code contains any nested codes, remove them (for single code subcauses that are totals of decimal subcauses):
                if (len(c2) == 3 | (len(c2) == 5 and "." in c2)) and len(test_data[c2]['codes_removed']):
                    for nested in test_data[c2]['codes_removed']:
                        test_data[c]['subcauses_remaining'].append(nested)
                        test_data[c]['subcodes'].append(nested)
                    print '     {} contains subcauses of {} ({})'.format(c2,c,test_data[c2]['codes'] + test_data[c2]['codes_removed'])
                else: print '     {} contains subcauses of {} ({})'.format(c2,c,test_data[c2]['codes'])
                ## Ensure unique entries (probably not necessary)
                test_data[c]['subcauses_remaining'] = list(set(test_data[c]['subcauses_remaining']))
            ## Alert of overlaps
            elif any(i in test_data[c2]['codes'] for i in test_data[c]['codes']) and len(test_data[c2]['codes']) < len(test_data[c]['codes']): 
                text = 'Overlap detected between {} and {} in {} \n'.format(c, c2, data_folder)
                # print text                    
                f = open(exception_location, 'a+')                        
                f.write(text)
                f.close()
                break
            else:
                # print '%s is NOT a subcause of %s' % (c2,c)
                pass
            
    # Set cause level
    highest_level = 0
    for c in test_data:
        #print '{} {}'.format(c, test_data[c]['num_subs_remaining'])
        num_subs_remaining = len(test_data[c]['subcauses_remaining'])
        test_data[c]['num_subs_remaining'] = num_subs_remaining
        if num_subs_remaining > highest_level: highest_level = num_subs_remaining

    if 'subcauses' not in test_data[c]: test_data[c]['subcauses'] = test_data[c]['subcauses_remaining']    
    
    # Return
    return (test_data, highest_level)

## subtract cause data (children) from subtotals (parents)
def remove_subcauses(test_data):
    print "removing subcauses..."
    subcauses_removed = False
    for possible_parent in test_data:
        ## only check possible parent codes that still have subcauses and codes
        if not test_data[possible_parent]['num_subs_remaining'] : continue
        ##  check against only codes with no subcauses and not against itself
        for possible_child in test_data:
            if test_data[possible_child]['num_subs_remaining'] or possible_parent == possible_child: continue
            ## if all codes are contained within the codes of the possible parent and the cause hasn't already been removed from the parent, subtract the child data from the parent
            elif set(test_data[possible_child]['codes']) <= set(test_data[possible_parent]['subcodes']) and not any(x in test_data[possible_parent]['codes_removed'] for x in test_data[possible_child]['codes']):               
                temp = test_data[possible_parent]['data'].sub(test_data[possible_child]['data'])
                if any(x < -1 for x in temp['metric']) and not negative_data_ok: 
                    print "ERROR: negative values occur when removing {} from {}".format(possible_child, possible_parent)
                    CRASH
                temp['metric'][temp['metric'] < 0] = 0
                ## remove the child codes from the parent
                test_data[possible_parent]['data'] = temp
                test_data[possible_parent]['codes'] = [x for x in test_data[possible_parent]['codes'] if x not in test_data[possible_child]['codes']]
                test_data[possible_parent]['subcodes'] = [x for x in test_data[possible_parent]['subcodes'] if x not in test_data[possible_child]['codes']]
                test_data[possible_parent]['codes_removed'] += test_data[possible_child]['codes']
                test_data[possible_parent]['causes_removed'].append(possible_child)
                subcauses_removed = True 
    return (test_data, subcauses_removed)
                   
    

## remove duplicates generated by disaggregation
def remove_duplicates(test_data):
    duplicates = {}
    ## determine if any causes now contain equivalent codes (redundancy) 
    for c in test_data:
        if not len(test_data[c]['codes']): continue
        for c2 in test_data:
            if c == c2 or not len(test_data[c2]['codes']): continue
            elif test_data[c]['codes'] == test_data[c2]['codes']:
                print '     {} redundant with {} ({}). Removing redundancy.'.format(c,c2, test_data[c]['codes'])
                redundant_codes = str.join(",", test_data[c]['codes'])
                if redundant_codes not in duplicates: duplicates[redundant_codes] = []
                duplicates[redundant_codes].append(c)
                duplicates[redundant_codes].append(c2)
                duplicates[redundant_codes] = list(set(duplicates[redundant_codes]))
            # else: print '{} NOT redundant with {}'.format(c,c2)
    ## for each redundancy, replace the first of cause with the mean values for the codes and remove values for the rest
    for redundant_codes in duplicates:
        new_data = test_data[duplicates[redundant_codes][0]]['data']
        codes = test_data[duplicates[redundant_codes][0]]['codes']
        ## add the data for all causes with the redundant code. it will next be divided by the number of causes to create the mean        
        for i in range(1, len(duplicates[redundant_codes])):
            new_data = new_data.add(test_data[duplicates[redundant_codes][i]]['data'])
            ## set the metric data for the cause that will not be kept to 0
            test_data[duplicates[redundant_codes][i]]['data']['metric'] *= 0
            test_data[duplicates[redundant_codes][i]]['codes'] = []
            test_data[duplicates[redundant_codes][i]]['codes_removed'] += codes
            if len(test_data[duplicates[redundant_codes][0]]['codes_removed']):
                test_data[duplicates[redundant_codes][i]]['causes_removed'].append("remainder of {} ({})".format(duplicates[redundant_codes][0] ,redundant_codes))
            else: test_data[duplicates[redundant_codes][i]]['causes_removed'].append(duplicates[redundant_codes][0])
        ## divide the data sum by the number of redundant causes to create the mean
        new_data['metric'] = new_data['metric'].div(len(duplicates[redundant_codes]))
        ## set the mean as the data for only the first copy of the code
        test_data[duplicates[redundant_codes][0]]['data'] = new_data
    return (test_data)    
    
def convert_to_range(code_range):
    p = []
    decimal_code_range = []
    has_c_codes = False

    for letter in ['C','D']:
        last = -2                                                            
        first = -1
        for code in sorted(set(code_range)):
            if letter == 'D' and has_c_codes: 
                p = add_codes(p, int(first), int(last), 'C', 1)
                has_c_codes = False
            if code[:1] == letter:
                if "." in code:
                    if int(float(code.replace(letter, "")[:2])) == int(last): 
                        continue
                    else:
                        decimal_code_range.append(code)
                        continue
                if float(code.replace(letter, "")[:2]) > last + 1 :
                    p = add_codes(p, int(first), int(last), letter, 1)
                    first = float(code.replace(letter, "")[:2])
                    if letter == 'C': has_c_codes = True
                last = float(code.replace(letter, "")[:2])
        p = add_codes(p, int(first), int(last), letter, 1)
                
    if len(decimal_code_range):
        has_c_codes = False
        for letter in ['C','D']:
            last = -2                                                            
            first = -1
            for code in sorted(set(decimal_code_range)):
                if letter == 'D' and has_c_codes: 
                    p = add_codes(p, first, last, 'C', .1)
                    has_c_codes = False
                if code[:1] == letter:
                    if round(float(code.replace(letter, "")), 3) > round(last + .1, 3):
                        p = add_codes(p, first, last, letter, .1)
                        first = float(code.replace(letter, ""))
                        if letter == 'C': has_c_codes = True
                    last = float(code.replace(letter, ""))
                    
        p = add_codes(p, first, last, letter, .1)
    return(sorted(p))
    
def add_codes(p, first, last, letter, delta):
    s_first = str(first) if first >= 10 else '0{}'.format(first)
    s_last = str(last) if last >= 10 else '0{}'.format(last)
    if first != -1 and first != last and last > round(first + delta, 3):
        p.append('{}{}-{}{}'.format(letter, s_first, letter, s_last))
    elif first != -1 and first != last and last == round(first + delta, 3):
        p.append(letter + s_first)
        p.append(letter + s_last)
    elif first != -1:
        p.append(letter + s_first)
    return(p)

## #########################
## Run Program
## ##########################
# Import data
oc = pd.read_stata(data_folder+'/original_code_list.dta')
input_dataset = pd.read_stata(data_folder+'/inputs/input_data.dta')
        
## For each uniqid found in code_breakdowns.dta...
for uid in sorted(oc['uniqid'].drop_duplicates()):
    print('\n uid: {}'.format(uid))

    ## add data for the given uid
    dt = input_dataset[input_dataset['uniqid'] == uid]
    colnames =[col for col in dt.columns if 'metric' in col]
    colnames.append('cause')
    dt = dt[colnames]
    dt = pd.melt(dt, id_vars = ['cause'], var_name='age', value_name='metric')
    pre_sd_sums = dt.groupby(['age']).sum()
    
    ## Loop through the causes for the given uid to create a list of subcauses 
    oc_uid = oc[oc.uniqid == uid]
    
    ## Create a list of possible codes so that decimal subcauses are only added if available
    input_cause_list = []
    for c in sorted(oc_uid['orig'].unique().tolist()):
       input_cause_list.append(c) 
    
    ## create a dictionary for codes in the selected uid and attach the uid's data
    uid_set = {}
    input_data = {} 
    for c in sorted(oc_uid['orig'].unique().tolist()):  # process decimals first and ranges last to ensure that nested causes are removed
        uid_set[c] = {}
        input_data[c] = {}
        uid_set[c]['codes'] = []
        uid_set[c]['subcodes'] = []
        if "-" not in c and "," not in c:
            uid_set[c]['codes'].append(c)
            for subcode in sorted(oc_uid['cause'].where(oc_uid['orig'] == c).dropna().unique().tolist()):
                if subcode != c: uid_set[c]['subcodes'].append(subcode)
            ## if none of the subcodes appear in the list, set the cause as a subcode of itself (prevents the addition of unused decimal causes)    
            if not len(uid_set[c]['subcodes']): uid_set[c]['subcodes'] = uid_set[c]['codes']
            elif not any('{}.'.format(sub[:3]) in check for check in input_cause_list for sub in uid_set[c]['subcodes']):
                uid_set[c]['subcodes'] = uid_set[c]['codes'] 
        else:
            for code in sorted(oc_uid['cause'].where(oc_uid['orig'] == c).dropna().unique().tolist()):
                uid_set[c]['codes'].append(code)     
                uid_set[c]['subcodes'].append(code)
       
        ## create other lists associated with the cause and add the metric data
        uid_set[c]['subcauses_remaining'] = []
        uid_set[c]['codes_removed'] = []
        uid_set[c]['causes_removed'] = []
        uid_set[c]['data'] = dt[dt['cause']==c][['age', 'metric']].set_index('age')
        input_data[c]['data'] = uid_set[c]['data']
        input_data[c]['codes'] = uid_set[c]['codes']
    
    ## Determine subcauses and highest number of causes remaining (how many subcauses are contained within each cause)
    uid_set, highest_level = set_subcauses(uid_set)     
        
    ## remove lowest level codes from parent causes
    if highest_level == 0: 
        print 'NO DISAGGREGATION AVAILABLE'
    else:
        subcauses_removed = True
        while subcauses_removed:
            uid_set, subcauses_removed = remove_subcauses(uid_set)
            ## remove duplicates
            uid_set = remove_duplicates(uid_set)            
            ## re-set subcauses and num_subs_remaining
            uid_set, highest_level = set_subcauses(uid_set)
        print "     no subcauses remaining."
    
    ## Prepare Output
    print "saving output..."
    output = pd.DataFrame(columns = ['cause', 'codes_remaining', 'codes_removed', 'age', 'metric'])
    for c in uid_set:
        ## format cause information
        cause_data = pd.DataFrame(columns = ['cause', 'codes_remaining', 'codes_removed'])               
        cause_data.loc[0, ['cause']] = c
        ## if nothing was removed, or there was only a single cause, or all of the input codes are still present, set the codes remaining as the cause
        if not len(uid_set[c]['codes_removed']) or ("-" not in c and "," not in c) or set(input_data[c]['codes']) <= set(uid_set[c]['codes']):
            cause_data.loc[0, ['codes_remaining']] = c
        else:  cause_data.loc[0, ['codes_remaining']] = ','.join(convert_to_range(uid_set[c]['codes']))
        cause_data.loc[0, ['codes_removed']] = ','.join(convert_to_range(uid_set[c]['codes_removed']))
        ## format output data        
        output_data = uid_set[c]['data']
        output_data['age'] = output_data.index
        output_data['cause'] = c
        orig_data = input_data[c]['data']
        orig_data['age'] = orig_data.index
        orig_data = orig_data.rename(columns={'metric': 'orig_metric_value'})
        orig_data['cause'] = c
        ## combine and add to output
        final = pd.merge(output_data, cause_data, on = 'cause')
        final = pd.merge(final, orig_data, on = ['cause', 'age'])
        output = output.append(final)
        
    ## Verify Data
    post_sd_sums = output.groupby(['age']).sum()        
    #if not post_sd_sums['metric'].equals(pre_sd_sums) : CRASH    
    
    ## Export results
    output['uniqid'] = uid
    output.set_index('cause').to_stata(data_folder+'/outputs/uid_'+str(uid)+'_output.dta')

print '\n Done!'

time.sleep(1) 


    