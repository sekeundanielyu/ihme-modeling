"""

Purpose: Determines which codes are contained within an aggregate code
"""

import pandas as pd
import copy, sys, platform

# print message
print("Determining code components...")

#Set Directories
if platform.system() == 'Linux':
    j = "/home/j"
elif platform.system() == 'Windows':
    j = "J:"

# assign data location and data type. accept arguments if they are sent.
if len(sys.argv) == 1:
    temp_folder = 'J:/temp/registry/cancer/01_inputs/subtotal_disagg/CI5/ci5_plus_summary_inc'
    data_type = 'inc'
    data_folder = temp_folder + '/temp_' + data_type
else:
    data_folder = sys.argv[1]
    data_type = sys.argv[2]

# Import list of codes in the dataset
import_df = pd.read_stata(data_folder+'/02_code_components_raw.dta')

# Keep only unique values for ICD codes in the dataset
unique_df = import_df[['coding_system','orig']].drop_duplicates()
unique_df.sort(['orig'],inplace=True)
input_codes = tuple(unique_df['orig'])

## Import list of ICD10 codes and define code index
ICD10_code_list = pd.read_csv(j + "/WORK/07_registry/cancer/00_common/data/Official_ICD10/list_of_official_NUMERIC_ICD10_codes.csv")
ICD10_code_list.sort(['ICD10_code'],inplace=True)
ICD10_code_list = tuple(ICD10_code_list['ICD10_code'])

## Add codes to the code index and attaches a number indicating their order
## Also mark codes as 'viable' if they are in the input dataset or are on the official list of ICD10 codes
code_index_ICD10 = {}
order_num = 1
for k in ['C','D']:
    under_10_alternate =  ['00', '01', '02', '03', '04', '05', '06', '07', '08', '09'] 
    
    for o in under_10_alternate + range(10,100):
        kode = '{}{}'.format(k,o) 
        code_index_ICD10[kode] = {}
        code_index_ICD10[kode]['order'] = order_num
        if kode in ICD10_code_list or kode in input_codes: code_index_ICD10['{}{}'.format(k,o)]['viable'] = True
        else: code_index_ICD10[kode]['viable'] = False
        order_num += 1     
        
        for d in range(0,10):
            kode = '{}{}.{}'.format(k,o,d)
            code_index_ICD10[kode] = {}
            code_index_ICD10[kode]['order'] = order_num
            if kode in ICD10_code_list or kode in input_codes: code_index_ICD10['{}{}.{}'.format(k,o,d)]['viable'] = True
            else: code_index_ICD10[kode]['viable'] = False
            order_num += 1  
             
            for e in range(0,10):
                kode = '{}{}.{}{}'.format(k,o,d,e)
                code_index_ICD10[kode] = {}
                code_index_ICD10[kode]['order'] = order_num
                if kode in ICD10_code_list or kode in input_codes: code_index_ICD10[kode]['viable'] = True
                else: code_index_ICD10[kode]['viable'] = False
                order_num += 1  
                    
# Prepare export file
export_df = {}
export_df['orig'] = []
export_df['cause'] = []
export_df['coding_system'] = []

# For each uniqe ICD code value...
for i in unique_df.index:
    coding_system = unique_df['coding_system'].ix[i]
    orig_cause = unique_df['orig'].ix[i]
    print '{}'.format(orig_cause)

    cause = {}
    cause['targets'] = {}
    cause['exclude'] = {}
    
    # Get list of all cancer codes
    if coding_system == "ICD10":
        code_index = copy.deepcopy(code_index_ICD10)
    else:
        print "ERROR: ICD9_detail cannot be disaggregated." 
        break
    
    # Mark any exclusions (excample: "C10-20 excl C15"). Break if there are multiple 'excl' clauses
    if len(orig_cause.split('excl')) > 2:
        print "ERROR: Breaking when splitting on exclusions for code:\n%s" % (orig_cause)
        break
    elif len(orig_cause.split('excl')) == 2:
        cause['exclude']['orig'] = orig_cause.split('excl')[1].replace(' ','')
        cause['targets']['orig'] = orig_cause.split('excl')[0].replace(' ','')
    else:
        cause['exclude']['orig'] = ''
        cause['targets']['orig'] = orig_cause.split('excl')[0].replace(' ','')
        
    # Split comma-separated ICD codes/groups into a list of individual codes/groups
    for t in ['exclude','targets']:
        cause[t]['intermediate'] = cause[t]['orig'].split(',')
        
    # Create a list of possible subcauses
    first_code_letter = cause['targets']['orig'].split(',')[0][:1]
    for t in ['exclude','targets']:
        cause[t]['final'] = []
        for c in cause[t]['intermediate']:
            ## Handle single integer codes: if an integer with decimal subcodes, create a list of decimal subcodes
            ## Add only sub-codes with one decimal place
            if not '.' in c and len(c) == 3:
                for test_code in code_index:
                    if c == test_code[:3] and 3 <= len(test_code) <= 5 and code_index[c]['order'] <= code_index[test_code]['order'] and code_index[test_code]['viable']:
                        cause[t]['final'].append(test_code)
            
            ## Handle single decimal codes: if an integer with decimal subcodes, create a list of decimal subcodes
            ## Add only sub-codes with two decimal places
            if '.' in c and not '-' in c and len(c) == 5:  
                for test_code in code_index:
                    if c == test_code[:5] and 5 <= len(test_code) <= 6 and code_index[c]['order'] <= code_index[test_code]['order'] and code_index[test_code]['viable']:
                        cause[t]['final'].append(test_code)
            
            ## Handle cause aggregates: create a list of all codes contained within the aggregate
            elif '-' in c:
                ## add first letter to beginning of range. if there are no letters, break
                if c[:1] != "C" and c[:1] != "D" and c != '':
                    if first_code_letter == '':
                        print "ERROR: Start code in %s does not have C or D in first character" % (c)
                        break
                    else: c = first_code_letter.append(c)
                
                ## if there are more than two codes in a range, break
                if len(c.split('-')) != 2:
                    print "ERROR: More or fewer than 2 items when splitting range for code:\n%s" % (c)
                    break
                
                ## set the start and stop codes
                range_start_code = c.split('-')[0]
                range_end_code = c.split('-')[1]
                
                ## add the first letter to the end code of the range, if not present. NOTE: assumes that ranges contain only one letter type
                if range_end_code[:1] not in ['C', 'D']: range_end_code = first_code_letter + range_end_code
                    
                # Ensure that range_start and range_end have at least 3 characters
                if len(range_start_code) <= 2:
                    print "ERROR: Start code in {} does not have enough characters".format(c)
                    break
                if len(range_end_code) == 2:
                    if int(range_start_code[2:3]) > int(range_end_code[1:2]):
                        print "ERROR: End code in {} is less than start code".format(c)
                        break
                    range_end_code_tens = int(range_start_code[1:2])
                    range_end_code = range_end_code[:1] + str(range_end_code_tens) + range_end_code[1:2]
                elif len(range_end_code) < 2:
                    print "ERROR: End code in {} is not in readable format".format(c)
                    break
                
                ## Compile list of codes within ranges. 
                for test_code in code_index:
                    if (("." in c and "." in test_code) or ("." not in c and "." not in test_code)):
                        test_code_order = code_index[test_code]['order']
                        if test_code_order >= code_index[range_start_code]['order'] and test_code_order <= code_index[range_end_code]['order']:
                             if not ("." in c and not code_index[test_code]['viable']):
                                    cause[t]['final'].append(test_code)
           
            ## Handle all other codes (if nothing has been added, mark the code as itself)
            if cause[t]['final'] == []: 
                    cause[t]['final'].append(c)
                
    ## Remove from final list those codes that were excluded from aggregates
    final_cause_list = copy.deepcopy(cause['targets']['final'])
    for ec in cause['exclude']['final']:
        for tc in cause['targets']['final']:
            if ec in tc and ec != '':
                final_cause_list.remove(tc)

    for c in final_cause_list:
        export_df['orig'].append(orig_cause)
        export_df['cause'].append(c)
        export_df['coding_system'].append(coding_system)
        
export_df = pd.DataFrame(export_df)
export_df.set_index('cause').to_stata(data_folder+'/02_code_components_split.dta')

print 'Done!'

