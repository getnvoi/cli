NVOI = ruby -I$(PWD)/lib $(PWD)/exe/nvoi
EXAMPLES = $(PWD)/../nvoi-cli/examples

deploy-golang:
	cd $(EXAMPLES)/golang && $(NVOI) deploy

exec-golang:
	cd $(EXAMPLES)/golang && $(NVOI) exec -i

show-golang:
	cd $(EXAMPLES)/golang && $(NVOI) credentials show

delete-golang:
	cd $(EXAMPLES)/golang && $(NVOI) delete

deploy-rails:
	cd $(EXAMPLES)/rails-single && $(NVOI) deploy

delete-rails:
	cd $(EXAMPLES)/rails-single && $(NVOI) delete

test:
	bundle exec rake test

lint:
	bundle exec rubocop
