package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/meirdev/network-monitoring/api/common"
	"github.com/meirdev/network-monitoring/api/services"
)

type GetTopParams struct {
	Column string `form:"column" binding:"required,oneof=src_addr dst_addr src_port dst_port etype proto tcp_flags sampler_address dst_as src_as"`
	K      *int   `form:"k" binding:"omitempty,numeric,gt=0"`
	Agg    string `form:"agg" binding:"required,oneof=bytes packets"`
}

type DashboardController struct {
	DashboardService *services.DashboardService
}

func NewDashboardController(dashboardService *services.DashboardService) *DashboardController {
	return &DashboardController{
		DashboardService: dashboardService,
	}
}

func (c *DashboardController) GetTop(ctx *gin.Context) {
	var params GetTopParams
	if err := ctx.ShouldBindQuery(&params); err != nil {
		ctx.JSON(http.StatusBadRequest, common.NewResponseWithError(err))
		return
	}

	result, err := c.DashboardService.GetKTop(ctx.Request.Context(), params.Column, params.K, params.Agg)
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(result))
}
