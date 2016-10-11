cap program drop gen_tmrel_mid
program define gen_tmrel_mid
    args risk risk_id

    import delimited using "$experimental_dir/risk_utils/resources/risk_variables.csv", clear
    keep if risk=="`risk'"
    gen tmrel_mid = (((tmred_para2 - tmred_para1)/2) + tmred_para1)/rr_scalar
    gen risk_id = `risk_id'
    rename minval min_val

    keep risk_id tmrel_mid rr_scalar inv_exp min_val
end
// END
