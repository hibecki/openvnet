package openvnet

import (
	"net/http"
)

const Namespace = "networks"

type Network struct {
	ID           int    `json:"id"`
	UUID         string `json:"uuid"`
	DisplayName  string `json:"display_name"`
	Ipv4Network  string `json:"ipv4_network"`
	Ipv4Prefix   string `json:"ipv4_prefix"`
	NetworkMode  string `json:"network_mode"`
	DomainName   string `json:"domain_name"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
	DeletedAt    string `json:"deleted_at"`
	SegmentID    int    `json:"segment_id"`
	IsDeleted    bool   `json:"id_deleted"`
}

type NetworkService struct {
	client *Client

	Namespace string
}

type NetworkCreateParams struct {
	UUID         string `url:"uuid,omitempty"`
	DisplayName  string `url:"display_name,omitempty"`
	Ipv4Network  string `url:"ipv4_network"`
	Ipv4Prefix   string `url:"ipv4_prefix,omitempty"`
	NetworkMode  string `url:"network_mode"`
	DomainName   string `url:"domain_name,omitempty"`
	SegmentUUID  string `url:"segment_id,omitempty"`
}

func (s *NetworkService) Create (params *NetworkCreateParams) (*Network, *http.Response, error) {
	nw := new(Network)
	ovnError := new(OpenVNetError)
	resp, err := s.client.sling.New().Post(Namespace).BodyForm(params).Receive(nw, ovnError)
	return nw, resp, err

}

func (s *NetworkService) Delete (id string) (*http.Response, error) {
	return s.client.sling.New().Delete(s.Namespace +"/"+ id).Receive(nil, new(OpenVNetError))
}
