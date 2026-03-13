TF_VPN=terraform/environments/dr/vpn
TF_ETCD=terraform/environments/dr/etcd
TF_PATRONI=terraform/environments/dr/patroni
ANS=ansible

VPN_INV=inventory/dr/hosts.yml
ETCD_INV=generated/inventory/etcd.yml
PATRONI_INV=generated/inventory/patroni.yml

.PHONY: terraform-vpn-plan terraform-vpn-apply ansible-vpn vpn
.PHONY: terraform-etcd-plan terraform-etcd-apply ansible-etcd etcd
.PHONY: terraform-patroni-plan terraform-patroni-apply ansible-patroni patroni

terraform-vpn-plan:
	terraform -chdir=$(TF_VPN) init
	terraform -chdir=$(TF_VPN) plan

terraform-vpn-apply:
	terraform -chdir=$(TF_VPN) init
	terraform -chdir=$(TF_VPN) apply

ansible-vpn:
	cd $(ANS) && ansible-playbook -i $(VPN_INV) playbooks/vpn.yml

vpn: terraform-vpn-apply ansible-vpn

terraform-etcd-plan:
	terraform -chdir=$(TF_ETCD) init
	terraform -chdir=$(TF_ETCD) plan

terraform-etcd-apply:
	terraform -chdir=$(TF_ETCD) init
	terraform -chdir=$(TF_ETCD) apply

ansible-etcd:
	cd $(ANS) && ansible-playbook -i ../$(ETCD_INV) playbooks/etcd.yml

etcd: terraform-etcd-apply ansible-etcd

terraform-patroni-plan:
	terraform -chdir=$(TF_PATRONI) init
	terraform -chdir=$(TF_PATRONI) plan

terraform-patroni-apply:
	terraform -chdir=$(TF_PATRONI) init
	terraform -chdir=$(TF_PATRONI) apply

ansible-patroni:
	cd $(ANS) && ansible-playbook -i ../$(PATRONI_INV) playbooks/patroni.yml

patroni: terraform-patroni-apply ansible-patroni
