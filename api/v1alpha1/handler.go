package v1alpha1

import (
	"fmt"

	corev1 "k8s.io/api/core/v1"
)

type Handler struct {
	Runtime Runtime `json:"runtime" protobuf:"bytes,4,opt,name=runtime,casttype=Runtime"`
	Code    string  `json:"code" protobuf:"bytes,3,opt,name=code"`
}

func (in *Handler) getContainer(req getContainerReq) corev1.Container {
	return corev1.Container{
		Name:            CtrMain,
		Image:           fmt.Sprintf(req.imageFormat, "dataflow-"+in.Runtime),
		ImagePullPolicy: req.imagePullPolicy,
		VolumeMounts:    []corev1.VolumeMount{req.volumeMount},
		Resources:       LargeResourceRequirements,
		Lifecycle:       req.lifecycle,
	}
}
