/* Description: second program to call when creating multi-page pdfs; should follow the graph command; creates .ps files and adds them to the queue for distiller
*/

capture program drop pdfappend
program define pdfappend
	// the program will be called by typing -pdfappend-
	// it will continue using the pdfname defined in the previous -pdfstart- command

if "$pdfname" == "" {
	display in red "Error: You must first run -pdfstart- and define the pdf name and directory"
	error 197
}
	// make sure that pdfstart was run first

quietly graph export "$pdfdir/$pdfname/$current_graph.ps", replace
	// save the current graph as a .ps file

file open do_file using "$pdfdir/$pdfname.do", write append text
if c(os) == "Windows" {
	file write do_file `"erase "$pdfdir/$pdfname/$current_graph.ps""' _n
}
else if c(os) == "Unix" {
	file write do_file `"erase "$pdfdir/$pdfname/$current_graph.ps""' _n
}	
file close do_file
	// add this file to the list of .ps files we need to delete later

if c(os) == "Windows" {
	file open ps_file using "$pdfdir/$pdfname.ps", write append text
	file write ps_file `"($pdfdir/$pdfname/$current_graph.ps) prun"' _n
	file close ps_file
		// add this file to the list of .ps files that Distiller will combine into a single pdf
}
else if c(os) == "Unix" {
	global gs_cmd $gs_cmd $pdfdir_nospace/$pdfname_nospace/$current_graph.ps
		// add this file to the ghostscript command that we'll eventually run
}

global current_graph = $current_graph + 1
	// increase the graph counter

end
