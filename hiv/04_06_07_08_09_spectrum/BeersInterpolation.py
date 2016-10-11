import csv

# Import the file that contains Beers' coefficients
found_file = False
n_tries = 1
while not found_file and n_tries <= 20:
	try:
		BeersFileGroups = open('/strPath/BeersCoefficientsGroupsCopy.txt', 'r')
		found_file = True
	except:
		print 'Try #%i failed' % n_tries
		time.sleep(1)
		n_tries += 1
# Set BeersCoefficients to the object in the file.
BeersCoefficientsGroups = eval(BeersFileGroups.read())

# Import the file that contains Beers' coefficients
found_file = False
n_tries = 1
while not found_file and n_tries <= 20:
	try:
		BeersFilePoints = open('/strPath/BeersCoefficientsPointsCopy.txt', 'r')
		found_file = True
	except:
		print 'Try #%i failed' % n_tries
		time.sleep(1)
		n_tries += 1
# Set BeersCoefficients to the object in the file.
BeersCoefficientsPoints = eval(BeersFilePoints.read())

def BeersInterpolateGroups(points):
	'''Takes a list of five-unit spaced group values and
interpolates single ages using Beers.'''

		''' Initalize an empty list for the indices of the 5 values to
		be used in the estimation.'''
		selectedPointIndices = []

		''' Identify each value in points as either first, second,
		middle, next-to-last (NTLast), or last. This allows the script
		to select the appropriate indices to use in the estimation. We
		want the current value to be the middle term in the equation,
		but this is obviously not always possible. It also allows the
		script to select the correct set of coefficients.'''
		if i <= 1:
			if i == 0:
				currentID = 'firstInterval'
			else:
				currentID = 'secondInterval'
			for j in range(5):
				selectedPointIndices.append(j)
		elif i >= len(points) - 2:
			if i == len(points) - 1:
				currentID = 'lastInterval'
			else:
				currentID = 'NTLastInterval'
			for j in range(len(points) - 5, len(points)):
				selectedPointIndices.append(j)
		else:
			currentID = 'middleInterval'
			for j in range(i - 2, i + 3):
				selectedPointIndices.append(j)
		
		# Select the appropriate set of coefficients for the value.
		currentCoeffSet = BeersCoefficientsGroups[currentID]

		# Initialize a list to hold the projected values for the current interval
		intervalProjections = []
		''' We will want five values for each interval (corresponding
		to the five parts we are creating), so we iterate through the
		current set of coefficients, calculate the value for each part,
		and append them to the set-specific list'''
		for coeff in currentCoeffSet:
			# Create a temporary value to hold the single projections
			tempValue = 0
			''' Multiply each single coefficient by the corresponding
			value in the points list.'''
			for k in range(len(coeff)):
				tempValue += coeff[k] * points[selectedPointIndices[k]]
			intervalProjections.append(tempValue)

		# Append the new set-specific list to the final list of values.
		projectedValues.extend(intervalProjections)

	return projectedValues

def BeersInterpolatePoints(points):
	'''Takes a list of five-unit spaced group values and
interpolates single ages using Beers. Currently, the
.txt containing the list of coefficients is sitting
on my desktop.'''

	
	# Initialize an empty list for storing the projections
	projectedValues = []

	# Calculate the projected values for each value in points
	for i in range(len(points)-1):

		''' Initalize an empty list for the indices of the 5 values to
		be used in the estimation.'''
		selectedPointIndices = []

		''' Identify each value in points as either first, second,
		middle, next-to-last (NTLast), or last. This allows the script
		to select the appropriate indices to use in the estimation. We
		want the current value to be the middle term in the equation,
		but this is obviously not always possible. It also allows the
		script to select the correct set of coefficients.'''
		if i <= 1:
			if i == 0:
				currentID = 'firstInterval'
			else:
				currentID = 'secondInterval'
			for j in range(6):
				selectedPointIndices.append(j)
		elif i >= len(points) - 3:
			if i > len(points) - 3:
				currentID = 'lastInterval'
			else:
				currentID = 'NTLastInterval'
			for j in range(len(points) - 6, len(points)):
				selectedPointIndices.append(j)
		else:
			currentID = 'middleInterval'
			for j in range(i - 2, i + 4):
				selectedPointIndices.append(j)
		
		# Select the appropriate set of coefficients for the value.
		currentCoeffSet = BeersCoefficientsPoints[currentID]

		# Initialize a list to hold the projected values for the current interval
		intervalProjections = []
		''' We will want five values for each interval (corresponding
		to the five parts we are creating), so we iterate through the
		current set of coefficients, calculate the value for each part,
		and append them to the set-specific list'''
		for coeff in currentCoeffSet:
			# Create a temporary value to hold the single projections
			tempValue = 0
			''' Multiply each single coefficient by the corresponding
			value in the points list.'''
			for k in range(len(coeff)):
				tempValue += coeff[k] * points[selectedPointIndices[k]]
			intervalProjections.append(tempValue)
			intervalProjections[0] = points[i]

		# Append the new set-specific list to the final list of values.
		projectedValues.extend(intervalProjections)

	projectedValues.append(points[-1])
	return projectedValues
	
def openCSV(filepath):
	file = open(filepath, 'r')

	data = []

	with file as csvFile:
		reader = csv.reader(csvFile)
		for row in reader:
			data.append(row)
	return data
