package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/meirdev/network-monitoring/api/common"
	"github.com/meirdev/network-monitoring/api/services"
)

type RouterController struct {
	RouterService *services.RouterService
}

func NewRouterController(routerService *services.RouterService) *RouterController {
	return &RouterController{
		RouterService: routerService,
	}
}

func (c *RouterController) GetRouters(ctx *gin.Context) {
	routers, err := c.RouterService.GetRouters(ctx.Request.Context())
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(routers))
}

func (c *RouterController) GetRouter(ctx *gin.Context) {
	routerId := ctx.Param("router_id")

	router, err := c.RouterService.GetRouter(ctx.Request.Context(), routerId)
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(router))
}

func (c *RouterController) AddRouter(ctx *gin.Context) {
	var router services.Router
	if err := ctx.ShouldBindJSON(&router); err != nil {
		ctx.JSON(http.StatusBadRequest, common.NewResponseWithError(err))
		return
	}

	id, err := c.RouterService.AddRouter(ctx.Request.Context(), router)
	if err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	router.Id = *id

	ctx.JSON(http.StatusCreated, common.NewResponseSuccess(router))
}

func (c *RouterController) UpdateRouter(ctx *gin.Context) {
	var router services.Router
	if err := ctx.ShouldBindJSON(&router); err != nil {
		ctx.JSON(http.StatusBadRequest, common.NewResponseWithError(err))
		return
	}

	router.Id = ctx.Param("router_id")

	if err := c.RouterService.UpdateRouter(ctx.Request.Context(), router); err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess(router))
}

func (c *RouterController) DeleteRouter(ctx *gin.Context) {
	routerId := ctx.Param("router_id")

	if err := c.RouterService.DeleteRouter(ctx.Request.Context(), routerId); err != nil {
		ctx.JSON(http.StatusInternalServerError, common.NewResponseWithError(err))
		return
	}

	ctx.JSON(http.StatusOK, common.NewResponseSuccess[any](nil))
}
