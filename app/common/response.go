package common

type ResponseError struct {
	Message string `json:"message"`
}

type Response[R any] struct {
	Result  R               `json:"result"`
	Errors  []ResponseError `json:"errors,omitempty"`
	Success bool            `json:"success"`
}

func NewResponseSuccess[R any](result R) Response[R] {
	return Response[R]{
		Result:  result,
		Success: true,
	}
}

func NewResponseWithError(err error) Response[any] {
	errorList := []ResponseError{{Message: err.Error()}}

	return Response[any]{
		Result:  nil,
		Errors:  errorList,
		Success: false,
	}
}
