package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type RequestBody struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// stop diagnotics
func validateEmail(email string) error {
	return nil
}

func processData(data RequestBody) error {
	return nil
}

func handleRequest(c *gin.Context) {
	var reqBody RequestBody

	// This should be collapsed
	err := c.ShouldBindJSON(&reqBody)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid request body",
		})
		return err
	}

	// This should also be collapsed
	err = validateEmail(reqBody.Email)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid email",
		})
		return
	}

	// This should NOT be collapsed (different variable name)
	result := processData(reqBody)
	if result != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Processing failed",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Success",
	})
}

func handleWithError(c *gin.Context) {
	var reqBody RequestBody

	error := c.ShouldBindJSON(&reqBody)
	if error != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Failed to parse request",
		})
		return error
	}

	error = validateEmail(reqBody.Email)
	if error != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Email validation failed",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Success"})
}

func processWithNotOk(data RequestBody) error {
	notOk := validateData(data)
	if notOk != nil {
		logError(notOk)
		return notOk
	}

	notOk = saveToDatabase(data)
	if notOk != nil {
		logError(notOk)
		return notOk
	}

	return nil
}

func mixedIdentifiers(c *gin.Context) {
	var data RequestBody

	err := c.ShouldBindJSON(&data)
	if err != nil {
		return err
	}

	error := validateEmail(data.Email)
	if error != nil {
		logError(error)
		return
	}

	notOk := processData(data)
	if notOk != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": notOk.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Success"})
}

func validateData(data RequestBody) error {
	// validation logic
	return nil
}

func saveToDatabase(data RequestBody) error {
	// save logic
	return nil
}

func logError(err error) {
	// logging logic
}

func main() {
	r := gin.Default()
	r.POST("/submit", handleRequest)
	r.POST("/with-error", handleWithError)
	r.POST("/process", func(c *gin.Context) {
		var data RequestBody
		c.ShouldBindJSON(&data)
		err := processWithNotOk(data)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"message": "Processed"})
	})
	r.Run()
}
