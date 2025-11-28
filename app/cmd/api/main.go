package main

import (
	"context"
	"flag"
	"log"
	"os"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/gin-gonic/gin"

	"github.com/meirdev/network-monitoring/api/controllers"
	"github.com/meirdev/network-monitoring/api/services"
)

const DEFAULT_CLICKHOUSE_ADDR = "localhost:9000"
const DEFAULT_CLICKHOUSE_DATABASE = "flows"
const DEFAULT_CLICKHOUSE_USERNAME = "default"
const DEFAULT_CLICKHOUSE_PASSWORD = "password"

var (
	listenAddr = ":8090"
)

func main() {
	flag.StringVar(&listenAddr, "listen", listenAddr, "Address to listen on")
	flag.Parse()

	dbAddr, found := os.LookupEnv("CLICKHOUSE_ADDR")
	if !found {
		dbAddr = DEFAULT_CLICKHOUSE_ADDR
	}
	dbDatabase, found := os.LookupEnv("CLICKHOUSE_DATABASE")
	if !found {
		dbDatabase = DEFAULT_CLICKHOUSE_DATABASE
	}
	dbUsername, found := os.LookupEnv("CLICKHOUSE_USERNAME")
	if !found {
		dbUsername = DEFAULT_CLICKHOUSE_USERNAME
	}
	dbPassword, found := os.LookupEnv("CLICKHOUSE_PASSWORD")
	if !found {
		dbPassword = DEFAULT_CLICKHOUSE_PASSWORD
	}

	conn, err := clickhouse.Open(&clickhouse.Options{
		Addr: []string{dbAddr},
		Auth: clickhouse.Auth{
			Database: dbDatabase,
			Username: dbUsername,
			Password: dbPassword,
		},
		TLS: nil,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	if err := conn.Ping(context.Background()); err != nil {
		log.Fatal(err)
	}

	router := gin.Default()

	ruleService := services.NewRuleService(conn)
	ruleController := controllers.NewRuleController(ruleService)

	rulesGroup := router.Group("/rules")
	{
		rulesGroup.GET("", ruleController.GetRules)
		rulesGroup.GET("/:rule_id", ruleController.GetRule)
		rulesGroup.POST("", ruleController.AddRule)
		rulesGroup.PUT("/:rule_id", ruleController.UpdateRule)
		rulesGroup.DELETE("/:rule_id", ruleController.DeleteRule)
	}

	routerService := services.NewRouterService(conn)
	routerController := controllers.NewRouterController(routerService)

	routersGroup := router.Group("/routers")
	{
		routersGroup.GET("", routerController.GetRouters)
		routersGroup.GET("/:router_id", routerController.GetRouter)
		routersGroup.POST("", routerController.AddRouter)
		routersGroup.PUT("/:router_id", routerController.UpdateRouter)
		routersGroup.DELETE("/:router_id", routerController.DeleteRouter)
	}

	dashboardService := services.NewDashboardService(conn)
	dashboardController := controllers.NewDashboardController(dashboardService)

	dashboardGroup := router.Group("/dashboard")
	{
		dashboardGroup.GET("/top", dashboardController.GetTop)
	}

	log.Println("Starting server on", listenAddr)
	if err := router.Run(listenAddr); err != nil {
		log.Fatal(err)
	}
}
