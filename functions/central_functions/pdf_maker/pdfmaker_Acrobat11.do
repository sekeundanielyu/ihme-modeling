/*
Description: install the 3 programs needed to create PDFs (pdfstart, pdfappend, pdffinish)
*/

if c(os) == "Windows" {
	quietly do "J:\Usable\Tools\ADO\pdfstart_Acrobat11.ado"
	quietly do "J:\Usable\Tools\ADO\pdfappend.ado"
	quietly do "J:\Usable\Tools\ADO\pdffinish.ado"
}
else if c(os) == "Unix" {
	quietly do "/home/j/Usable/Tools/ADO/pdfstart_Acrobat10.ado"
	quietly do "/home/j/Usable/Tools/ADO/pdfappend.ado"
	quietly do "/home/j/Usable/Tools/ADO/pdffinish.ado"
}
