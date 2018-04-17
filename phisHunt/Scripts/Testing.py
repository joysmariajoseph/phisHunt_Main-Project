def getopts(argv):
    opts = {}  # Empty dictionary to store key-value pairs.
    while argv:  # While there are arguments left to parse...
        if argv[0][0] == '-':  # Found a "-url value" pair.
            opts[argv[0]] = argv[1]  # Add key and value to the dictionary.
        argv = argv[1:]  # Reduce the argument list by copying it starting from index 1.
    return opts

if __name__ == '__main__':
    from sys import argv
    import re
    myargs = getopts(argv)
    if '-url' in myargs:  # Example usage.
        import Training
        vectorizer, lgs  = Training.TL()
        url_from_client= myargs['-url']
        X_predict = [url_from_client]
        X_predict = vectorizer.transform(X_predict)
        y_Predict = lgs.predict(X_predict)
        print(y_Predict)	#return predicted values to powershell

