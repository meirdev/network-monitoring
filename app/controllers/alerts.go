package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/meirdev/network-monitoring/api/common"
	"github.com/meirdev/network-monitoring/api/services"
)

type AlertController struct {
	AlertService *services.AlertService
}

func NewAlertController(alertService *services.AlertService) *AlertController {
	return &AlertController{
		AlertService: alertService,
	}
}

func (c *AlertController) GetThresholdAlerts(ctx *gin.Context) {
	result, err := c.AlertService.GetThresholdAlerts(ctx.Request.Context())
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(result))
}
