import pandas as pd
from glob import glob
import datetime

date = datetime.date.today().strftime('%d%b%Y').lower()
dist_dir = "strDir"
summary_files = glob("%s/*summary.csv" % (dist_dir))
draw_files = glob("%s/*draws.csv" % (dist_dir))

summary = []
for i, f in enumerate(summary_files):
    print i/len(f),
    summary.append(pd.read_csv(f))
summary = pd.concat(summary)

draws = []
for f in draw_files:
    draws.append(pd.read_csv(f))
draws = pd.concat(draws)

summary.sort(['yld_cause', 'grouping', 'severity']).to_csv(
    "strDir/3b_meps_severity_distributions_%s.csv" % (date), index=False)
summary.sort(['yld_cause', 'grouping', 'severity']).to_csv(
    "strDir/3b_meps_severity_distributions_current.csv", index=False)

draws.sort(['yld_cause', 'grouping', 'severity']).to_csv(
    "strDir/3b_meps_severity_distributions_1000_draws_%s.csv" % (date),
    index=False)
draws.sort(['yld_cause', 'grouping', 'severity']).to_csv(
    "strDir/3b_meps_severity_distributions_1000_draws_current.csv",
    index=False)
