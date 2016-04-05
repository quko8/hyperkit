require 'spec_helper'

describe Hyperkit::Client::Containers do

  let(:client) { lxd }

  describe ".containers", :vcr do

    it "returns an array of containers" do
      containers = client.containers
      expect(containers).to be_kind_of(Array)
    end

    it "makes the correct API call" do
      containers = client.containers
      assert_requested :get, lxd_url("/1.0/containers")
    end

    it "returns only the image names and not their paths" do

      body = { metadata: [
        "/1.0/containers/test1",
        "/1.0/containers/test2",
        "/1.0/containers/test3",
        "/1.0/containers/test4"
      ]}.to_json

      stub_get("/1.0/containers").
        to_return(ok_response.merge(body: body))

      containers = client.containers
      expect(containers).to eq(%w[test1 test2 test3 test4])
    end

  end

  describe ".container", :vcr do

    it "retrieves a container", :container do
      container = client.container("test-container")
      expect(container.name).to eq("test-container")
      expect(container.architecture).to eq("x86_64")
    end

    it "makes the correct API call" do
      request = stub_get("/1.0/containers/test").to_return(ok_response)

      client.container("test")
      assert_requested request
    end

  end

  describe ".container_state", :vcr do

    it "returns the current state of a container", :container do
      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")
    end

    it "makes the correct API call" do
      request = stub_get("/1.0/containers/test/state").to_return(ok_response)

      client.container_state("test")
      assert_requested request
    end

  end

  describe ".create_container", :vcr, :skip_create do

    it "creates a container in the 'Stopped' state", :container do
      response = client.create_container("test-container", alias: "cirros")
      client.wait_for_operation(response.id)

      container = client.container("test-container")
      expect(container.status).to eq("Stopped")
    end

    it "passes on the container name" do
      request = stub_post("/1.0/containers").
        with(body: hash_including({
          name: "test-container",
          source: { type: "image", alias: "busybox" }
        })).
        to_return(ok_response)

      client.create_container("test-container", alias: "busybox")
      assert_requested request
    end

    context "when an architecture is specified" do

      it "passes on the architecture" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            architecture: "x86_64",
            source: { type: "image", alias: "busybox" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "busybox",
          architecture: "x86_64")

        assert_requested request
      end

    end

    context "when a list of profiles is specified" do

      it "passes on the profiles" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            profiles: ['test1', 'test2'],
            source: { type: "image", alias: "busybox" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "busybox",
          profiles: ['test1', 'test2'])

        assert_requested request
      end

      it "applies the profiles to the newly-created container", :container, :profiles do

        create_test_container("test-container",
          empty: true,
          profiles: %w[test-profile1 test-profile2])

        container = client.container("test-container")
        expect(container.profiles).to eq(%w[test-profile1 test-profile2])
      end

    end

    context "when 'ephemeral: true' is specified" do

      it "passes it along" do

        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            ephemeral: true,
            source: { type: "image", alias: "busybox" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "busybox",
          ephemeral: true)

        assert_requested request
      end

      it "makes the container ephemeral", :container do
        create_test_container("test-container", ephemeral: true, empty: true)

        container = client.container("test-container")
        expect(container).to be_ephemeral
      end

    end

    context "when 'ephemeral: true' is not specified" do

      it "defaults to a persistent container", :container do
        create_test_container("test-container", empty: true)

        container = client.container("test-container")
        expect(container).to_not be_ephemeral
      end

    end

    context "when a config hash is specified" do

      it "passes on the configuration" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
              name: "test-container",
              config: { hello: "world" },
              source: { type: "image", alias: "busybox" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "busybox",
          config: { hello: "world" })

        assert_requested request
      end

      it "stores the configuration with the container", :container do

        create_test_container("test-container",
          config: { "volatile.eth0.hwaddr" => "aa:bb:cc:dd:ee:ff" },
          empty: true)

        container = client.container("test-container")
        expect(container.config["volatile.eth0.hwaddr"]).to eq("aa:bb:cc:dd:ee:ff")
      end

      it "accepts non-String values", :container do

        create_test_container("test-container",
          config: { "limits.cpu" => 2 },
          empty: true)

        container = client.container("test-container")
        expect(container.config["limits.cpu"]).to eq("2")
      end

    end

    context "when an image is specified by alias" do

      it "passes on the alias" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", alias: "busybox" }
          })).
          to_return(ok_response)

        client.create_container("test-container", alias: "busybox")
        assert_requested request
      end

      it "creates a container by image alias", :container do
        create_test_container("test-container", alias: "cirros")
        container = client.container("test-container")

        image_alias = client.image_alias("cirros")
        expect(container.config["volatile.base_image"]).to eq(image_alias.target)
      end

    end

    context "when an image is specified by fingerprint" do

      it "passes on the fingerprint" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", fingerprint: "test-fingerprint" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          fingerprint: "test-fingerprint")

        assert_requested request
      end

      it "creates a container by image fingerprint", :container do
        fingerprint = client.image_by_alias("cirros").fingerprint
        response = client.create_container("test-container", fingerprint: fingerprint)
        client.wait_for_operation(response.id)

        container = client.container("test-container")
        expect(container.config["volatile.base_image"]).to eq(fingerprint)
      end

    end

    context "when 'empty: true' is specified" do

      it "passes the source type as 'none'" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "none" }
          })).
          to_return(ok_response)

        client.create_container("test-container", empty: true)
        assert_requested request
      end

      it "creates an empty container", :container do
        response = client.create_container("test-container",
          empty: true,
          config: { "volatile.eth0.hwaddr" => "aa:bb:cc:dd:ee:ff" }
        )
        client.wait_for_operation(response.id)

        container = client.container("test-container")
        expect(container.config["volatile.base_image"]).to be_nil
        expect(container.config["volatile.eth0.hwaddr"]).to eq("aa:bb:cc:dd:ee:ff")
      end

      [:alias, :certificate, :fingerprint, :properties, :protocol, :secret,:server].each do |prop|

        context "and the :#{prop} key is specified" do

          it "raises an error" do

            call = lambda do
               client.create_container("test-container",
                empty: true,
                prop => "test"
              )
            end

            expect(call).to raise_error(Hyperkit::InvalidImageAttributes)

          end

        end

      end

    end

    context "when an image is specified by properties" do

      it "passes on the properties" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", properties: { os: "busybox" } }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          properties: { os: "busybox" })

        assert_requested request
      end

      it "creates a container by image properties", :container do
        response = client.create_container("test-container",
          properties: { os: "Cirros", architecture: "x86_64" })
        client.wait_for_operation(response.id)

        container = client.container("test-container")
        fingerprint = client.image_by_alias("cirros").fingerprint
        expect(container.config["volatile.base_image"]).to eq(fingerprint)
      end

    end

    context "when no alias, fingerprint, properties, or empty: true are specified" do

      it "raises an error" do
        call = lambda { client.create_container("test-container") }
        expect(call).to raise_error(Hyperkit::ImageIdentifierRequired)
      end

    end

    context "when a fingerprint and alias are specified" do

      it "passes on the fingerprint" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", fingerprint: "test-fingerprint" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "test-alias",
          fingerprint: "test-fingerprint")

        assert_requested request
      end

    end

    context "when a fingerprint and properties are specified" do

      it "passes on the fingerprint" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", fingerprint: "test-fingerprint" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          fingerprint: "test-fingerprint",
          properties: { hello: "world" })

        assert_requested request
      end

    end

    context "when an alias and properties are specified" do

      it "passes on the alias" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", alias: "test-alias" }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "test-alias",
          properties: { hello: "world" })

        assert_requested request
      end

    end

    context "when no server is specified" do

      it "does not pass a mode" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: { type: "image", alias: "test-alias" }
          })).
          to_return(ok_response)

        client.create_container("test-container", alias: "test-alias")
        assert_requested request
      end

      [:protocol, :certificate, :secret].each do |prop|

        context "when the #{prop} option is passed" do

          it "raises an error" do

            call = lambda do
              client.create_container("test-container",
                alias: "test-alias",
                prop => "test")
            end

            expect(call).to raise_error(Hyperkit::InvalidImageAttributes)
          end

        end

      end

    end

    context "when a server is specified" do

      it "sets the mode to pull" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test-container",
            source: {
              type: "image",
              mode: "pull",
              server: "test-server",
              alias: "test-alias"
            }
          })).
          to_return(ok_response)

        client.create_container("test-container",
          alias: "test-alias",
          server: "test-server")

        assert_requested request
      end

      it "creates the container from a remote image", :container, :delete_image do
        image_alias = remote_lxd.image_alias("ubuntu/xenial/amd64")

        response = client.create_container("test-container",
          server: "https://images.linuxcontainers.org:8443",
          alias: "ubuntu/xenial/amd64")
        client.wait_for_operation(response.id)

        container = client.container("test-container")
        expect(container.config["volatile.base_image"]).to eq(image_alias.target)
      end

      context "when passed a protocol" do

        it "accepts lxd" do
          request = stub_post("/1.0/containers").
            with(body: hash_including({source: {
              type: "image",
              mode: "pull",
              server: "https://images.linuxcontainers.org:8443",
              protocol: "lxd",
              alias: "ubuntu/xenial/amd64",
            }})).
            to_return(ok_response)

          client.create_container("test-container",
            server: "https://images.linuxcontainers.org:8443",
            alias: "ubuntu/xenial/amd64",
            protocol: "lxd")

          assert_requested request
        end

        it "accepts simplestreams" do
          request = stub_post("/1.0/containers").
            with(body: hash_including({source: {
              type: "image",
              mode: "pull",
              server: "https://images.linuxcontainers.org:8443",
              protocol: "simplestreams",
              alias: "ubuntu/xenial/amd64",
            }})).
            to_return(ok_response)

          client.create_container("test-container",
            server: "https://images.linuxcontainers.org:8443",
            alias: "ubuntu/xenial/amd64",
            protocol: "simplestreams")

          assert_requested request
        end

        it "raises an error on invalid input" do

          call = lambda do
            client.create_container("test-container",
              server: "https://images.linuxcontainers.org:8443",
              alias: "ubuntu/xenial/amd64",
              protocol: "qwe")
          end

          expect(call).to raise_error(Hyperkit::InvalidProtocol)
        end

      end

      context "when passed a secret" do

        it "passes the secret to the server" do
          request = stub_post("/1.0/containers").
            with(body: hash_including({source: {
              type: "image",
              mode: "pull",
              server: "https://images.linuxcontainers.org:8443",
              secret: "reallysecret",
              alias: "ubuntu/xenial/amd64",
            }})).
            to_return(ok_response)

          client.create_container("test-container",
            server: "https://images.linuxcontainers.org:8443",
            alias: "ubuntu/xenial/amd64",
            secret: "reallysecret")

          assert_requested request
        end

      end

      context "when passed a certificate" do

        it "passes the certificate to the server" do
          request = stub_post("/1.0/containers").
            with(body: hash_including({source: {
              type: "image",
              mode: "pull",
              server: "https://images.linuxcontainers.org:8443",
              certificate: test_cert,
              alias: "ubuntu/xenial/amd64",
            }})).
            to_return(ok_response)

          client.create_container("test-container",
            server: "https://images.linuxcontainers.org:8443",
            alias: "ubuntu/xenial/amd64",
            certificate: test_cert)

          assert_requested request
        end

      end

    end

  end

  describe ".start_container", :vcr do

    it "starts a stopped container", :container do
      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")

      response = client.start_container("test-container")
      client.wait_for_operation(response.id)

      state = client.container_state("test-container")
      expect(state.status).to eq("Running")
    end

    it "accepts a timeout" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "start",
          timeout: 30
        })).
        to_return(ok_response)

      client.start_container("test", timeout: 30)
      assert_requested request
    end

    it "allows the operation to be stateful" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "start",
          stateful: true
        })).
        to_return(ok_response)

      client.start_container("test", stateful: true)
      assert_requested request
    end

  end

  describe ".stop_container", :vcr do

    it "stops a running container", :container, :running do
      state = client.container_state("test-container")
      expect(state.status).to eq("Running")

      response = client.stop_container("test-container", force: true)
      client.wait_for_operation(response.id)

      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")
    end

    it "throws an error if the container is not running", :container do
      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")

      response = client.stop_container("test-container")
      expect { client.wait_for_operation(response.id) }.to raise_error(Hyperkit::BadRequest)
    end

    it "accepts a timeout" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "stop",
          timeout: 30
        })).
        to_return(ok_response)

      client.stop_container("test", timeout: 30)
      assert_requested request
    end

    it "allows the operation to be forced" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "stop",
          force: true
        })).
        to_return(ok_response)

      client.stop_container("test", force: true)
      assert_requested request
    end

    it "allows the operation to be stateful" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "stop",
          stateful: true
        })).
        to_return(ok_response)

      client.stop_container("test", stateful: true)
      assert_requested request
    end

  end

  describe ".restart_container", :vcr do

    it "restarts a running container", :container, :running do
      state = client.container_state("test-container")
      expect(state.status).to eq("Running")
      pid_before = state.pid

      response = client.restart_container("test-container", force: true)
      client.wait_for_operation(response.id)

      state = client.container_state("test-container")
      expect(state.status).to eq("Running")
      pid_after = state.pid

      expect(pid_after).to_not eq(pid_before)
    end

    it "throws an error if the container is not running", :container do
      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")

      response = client.restart_container("test-container")
      expect { client.wait_for_operation(response.id) }.to raise_error(Hyperkit::BadRequest)
    end

    it "allows the operation to be forced" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "restart",
          force: true
        })).
        to_return(ok_response)

      client.restart_container("test", force: true)
      assert_requested request
    end

    it "accepts a timeout" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "restart",
          timeout: 30
        })).
        to_return(ok_response)

      client.restart_container("test", timeout: 30)
      assert_requested request
    end

  end

  describe ".freeze_container", :vcr do

    it "suspends a running container", :container, :running do
      state = client.container_state("test-container")
      expect(state.status).to eq("Running")

      response = client.freeze_container("test-container")
      client.wait_for_operation(response.id)

      state = client.container_state("test-container")
      expect(state.status).to eq("Frozen")
    end

    it "throws an error if the container is not running", :container do
      state = client.container_state("test-container")
      expect(state.status).to eq("Stopped")

      response = client.freeze_container("test-container")
      expect { client.wait_for_operation(response.id) }.to raise_error(Hyperkit::BadRequest)
    end

    it "accepts a timeout" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "freeze",
          timeout: 30
        })).
        to_return(ok_response)

      client.freeze_container("test", timeout: 30)
      assert_requested request
    end

  end

  describe ".unfreeze_container", :vcr do

    it "resumes a frozen container", :container, :frozen do
      state = client.container_state("test-container")
      expect(state.status).to eq("Frozen")

      response = client.unfreeze_container("test-container")
      client.wait_for_operation(response.id)

      state = client.container_state("test-container")
      expect(state.status).to eq("Running")
    end

    it "throws an error if the container is not frozen", :container, :running do
      state = client.container_state("test-container")
      expect(state.status).to eq("Running")

      response = client.unfreeze_container("test-container")
      expect { client.wait_for_operation(response.id) }.to raise_error(Hyperkit::BadRequest)
    end

    it "accepts a timeout" do
      request = stub_put("/1.0/containers/test/state").
        with(body: hash_including({
          action: "unfreeze",
          timeout: 30
        })).
        to_return(ok_response)

      client.unfreeze_container("test", timeout: 30)
      assert_requested request
    end

  end

  describe ".update_container", :vcr do

    it "updates the configuration of a container", :container, :running do
      container = client.container("test-container")
      expect(container.architecture).to eq("x86_64")
      expect(container.ephemeral).to be_falsy
      expect(container.devices.to_hash.keys).to eq([:root])

      container.architecture = "i686"
      container.devices.eth1 = {nictype: "bridged", parent: "lxcbr0", type: "nic"}

      response = client.update_container("test-container", container)
      client.wait_for_operation(response.id)

      container = client.container("test-container")
      expect(container.architecture).to eq("i686")
      expect(container.devices.to_hash.keys.sort).to eq([:eth1, :root])
      expect(container.devices.eth1.type).to eq("nic")
      expect(container.devices.eth1.parent).to eq("lxcbr0")
      expect(container.devices.eth1.nictype).to eq("bridged")
    end

    it "accepts non-String values", :container do

      container = client.container("test-container").to_hash
      container.merge!(config: container[:config].merge("limits.cpu" => 2))

      response = client.update_container("test-container", container)
      client.wait_for_operation(response.id)

      container = client.container("test-container")
      expect(container.config["limits.cpu"]).to eq("2")
    end

    it "makes the correct API call" do
      request = stub_put("/1.0/containers/test").
        with(body: hash_including({
          hello: "world"
        })).
        to_return(ok_response)

      client.update_container("test", {"hello": "world"})
      assert_requested request
    end

  end

  describe ".delete_container", :vcr, :skip_delete do

    it "deletes the container", :container do
      expect(client.containers).to include("test-container")

      response = client.delete_container("test-container")
      client.wait_for_operation(response.id)

      expect(client.containers).to_not include("test-container")
    end

    it "raises an exception if the container is running", :container, :running, skip_delete: false do
      call = lambda { client.delete_container("test-container") }
      expect(call).to raise_error(Hyperkit::BadRequest)
    end

    it "makes the correct API call" do
      request = stub_delete("/1.0/containers/test").to_return(ok_response)
      client.delete_container("test")
      assert_requested request
    end

  end

  describe ".rename_container", :vcr do

    it "renames a container", :container do
      @test_container_name = "test-container-2"

      expect(client.containers).to include("test-container")
      expect(client.containers).to_not include(@test_container_name)

      response = client.rename_container("test-container", @test_container_name)
      client.wait_for_operation(response.id)

      expect(client.containers).to_not include("test-container")
      expect(client.containers).to include(@test_container_name)
    end

    it "fails if the container is running", :container, :running do
      response = client.rename_container("test-container", "test-container-2")
      call = lambda { client.wait_for_operation(response.id) }
      expect(call).to raise_error(Hyperkit::BadRequest)
    end

    it "makes the correct API call" do
      request = stub_post("/1.0/containers/test").
        with(body: hash_including({
          name: "test2"
        })).
        to_return(ok_response)

      client.rename_container("test", "test2")
      assert_requested request
    end
  end

  describe ".init_container_migration", :vcr do

    it "returns secrets used by a target LXD instance to migrate a container", :container, :running do
      response = client.init_container_migration("test-container")

      expect(response.websocket.url).to_not be_nil
      expect(response.websocket.secrets.control).to_not be_nil
      expect(response.websocket.secrets.criu).to_not be_nil
      expect(response.websocket.secrets.fs).to_not be_nil
    end

    it "makes the correct API call" do
      request = stub_post("/1.0/containers/test").
        with(body: hash_including({
          migration: true
        })).
        to_return(ok_response.merge(body: { operation: "", metadata: { metadata: {} } }.to_json))

        stub_get("/1.0/containers/test").to_return(ok_response.merge(body: {
          metadata: {
            architecture: "x86_64",
            config: {}
          }
        }.to_json))

      client.init_container_migration("test")
      assert_requested request
    end

  end

  describe ".migrate_container", :vcr do

    let(:test_source) { test_migration_source }

    before(:each, remote_container: true) do
      response = lxd2.create_container("test-remote", alias: "cirros")
      lxd2.wait_for_operation(response.id)
    end

    before(:each, remote_running: true) do
      response = lxd2.start_container("test-remote")
      lxd2.wait_for_operation(response.id)
    end

    after(:each, remote_container: true) do
      response = lxd2.delete_container("test-remote")
      lxd2.wait_for_operation(response.id)
    end

    it "copies a container from a remote LXD instance", :container, :skip_create, :remote_container do

      source = lxd2.init_container_migration("test-remote")
      expect(client.containers).to_not include("test-container")

      response = client.migrate_container(source, "test-container")
      client.wait_for_operation(response.id)

      expect(client.containers).to include("test-container")
    end

    #TODO: when snapshots are implemented
    context "when the source is a snapshot" do
      it "does not pass a base-image"
    end
    
    context "when the source is an image" do

      it "passes a base-image" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
					  "base-image" => "test-base-image"
          })).
          to_return(ok_response.merge(body: { metadata: {} }.to_json))

        client.migrate_container(test_source, "test2")
        assert_requested request
      end

    end
    
    context "when move: true is specified" do

      it "does not remove volatile attributes" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
						config: {
              :"volatile.base_image"  => "test-base-image",
              :"volatile.eth0.hwaddr" => "test-eth0-hwaddr",
    				}
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", move: true)
				assert_requested request	
      end

    end
    
    context "when move: true is not specified" do

      it "removes volatile attributes" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
						config: {}
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2")
				assert_requested request	
      end

    end
    
    context "when an architecture is specified" do

      it "passes it to the server" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
						architecture: "custom-arch"
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", architecture: "custom-arch")
				assert_requested request	
			end

    end

		context "when no architecture is specified" do

      it "passes the source container's architecture" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
						architecture: "x86_64"
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2")
				assert_requested request	
			end

		end
    
    context "when a certificate is specified" do

      it "passes it as the source server's certificate" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            source: {
							type: "migration", 
              mode: "pull",
              operation: "test-ws-url",
              secrets: {
                control: "test-control-secret",
                fs: "test-fs-secret",
                criu: "test-criu-secret"
              },
						  certificate: "overridden"
            }
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", certificate: "overridden")
				assert_requested request	
			end

    end
    
    context "when no certificate is specified" do

      it "passes the certificate returned by the source server" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            source: {
							type: "migration", 
              mode: "pull",
              operation: "test-ws-url",
              secrets: {
                control: "test-control-secret",
                fs: "test-fs-secret",
                criu: "test-criu-secret"
              },
						  certificate: "test-certificate"
            }
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2")
				assert_requested request	
			end

    end
    
    context "when a config hash is specified" do

      it "passes it to the server" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            config: {
              hello: "world"
            }
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", config: { hello: "world" })
				assert_requested request	
      end

    end
    
    context "when no config hash is specified" do

      it "copies source container's configuration", :container, :skip_create, :remote_container do

        container = lxd2.container("test-remote")
        container.config = container.config.to_hash.merge("limits.memory" => "256MB")

        response = lxd2.update_container("test-remote", container)
        lxd2.wait_for_operation(response.id)

        source = lxd2.init_container_migration("test-remote")
        expect(client.containers).to_not include("test-container")

        response = client.migrate_container(source, "test-container")
        client.wait_for_operation(response.id)

        migrated = client.container("test-container")
        expect(migrated.config["limits.memory"]).to eq("256MB")

      end

    end
    
    context "when profiles are passed" do

      it "applies them to the migrated container" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            profiles: %w[test1 test2]
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", profiles: %w[test1 test2])
				assert_requested request	
      end

    end
    
    context "when no profiles are passed" do

      it "applies the profiles from the source container to the migrated container" do

        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            profiles: %w[default]
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2")
				assert_requested request	

      end
    
      context "and not all source profiles exist on the target server" do

        it "raises an error" do
          allow(client).to receive(:profiles) { [] }

          call = lambda { client.migrate_container(test_source, "test2") }
          expect(call).to raise_error(Hyperkit::MissingProfiles)
        end

      end
    
    end
     
    context "when ephemeral: true is specified" do

      it "makes the migrated container ephemeral" do
        allow(client).to receive(:profiles) { %w[default] }
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            ephemeral: true
          })).
          to_return(ok_response)

        client.migrate_container(test_source, "test2", ephemeral: true)
				assert_requested request	
      end

    end
    
    context "when ephemeral: true is not specified" do
      
      context "and the source container is ephemeral" do

        it "makes the migrated container ephemeral" do

          data = test_migration_source_data.merge(ephemeral: true)
          source = test_migration_source(data)

          allow(client).to receive(:profiles) { %w[default] }
          request = stub_post("/1.0/containers").
            with(body: hash_including({
              ephemeral: true
            })).
            to_return(ok_response)

          client.migrate_container(source, "test2")
				  assert_requested request	

        end

      end
    
      context "and the source container is persistent" do

        it "makes the source container persistent" do

          allow(client).to receive(:profiles) { %w[default] }
          request = stub_post("/1.0/containers").
            with(body: hash_including({
              ephemeral: false 
            })).
            to_return(ok_response)

          client.migrate_container(test_source, "test2")
				  assert_requested request	

        end
      end
    
    end

  end

  describe ".copy_container", :vcr do

    after(:each, :delete_copy) do
      response = client.delete_container("test-container2")
      client.wait_for_operation(response.id)
    end

    it "makes the correct API call" do
      request = stub_post("/1.0/containers").
        with(body: hash_including({
          name: "test2",
          source: { type: "copy", source: "test" }
        })).
        to_return(ok_response.merge(body: { metadata: {} }.to_json))

      client.copy_container("test", "test2")
      assert_requested request
    end

    it "copies a stopped container", :container, :delete_copy do
      response = client.copy_container("test-container", "test-container2")
      client.wait_for_operation(response.id)

      container1 = client.container("test-container")
      container2 = client.container("test-container2")

      img1 = container1.config["volatile.base_image"]
      img2 = container2.config["volatile.base_image"]

      expect(img1).to eq(img2)
      expect(container1.architecture).to eq(container2.architecture)
      expect(container1.profiles).to eq(container2.profiles)
    end

    it "copies a running container to a stopped target container", :container, :running, :delete_copy do
      response = client.copy_container("test-container", "test-container2")
      client.wait_for_operation(response.id)

      container1 = client.container("test-container")
      container2 = client.container("test-container2")

      img1 = container1.config["volatile.base_image"]
      img2 = container2.config["volatile.base_image"]

      expect(img1).to eq(img2)
      expect(container1.architecture).to eq(container2.architecture)
      expect(container1.profiles).to eq(container2.profiles)

      expect(container1.status).to eq("Running")
      expect(container2.status).to eq("Stopped")
    end

    it "fails if the target container already exists", :container do
      response = client.copy_container("test-container", "test-container")

      call = lambda do
        client.wait_for_operation(response.id)
      end

      expect(call).to raise_error(Hyperkit::BadRequest)
    end

    it "generates new MAC addresses for the target container", :container, :delete_copy do
      response = client.copy_container("test-container", "test-container2")
      client.wait_for_operation(response.id)

      container1 = client.container("test-container")
      container2 = client.container("test-container2")

      mac1 = container1.config["volatile.eth0.hwaddr"]
      mac2 = container2.config["volatile.eth0.hwaddr"]

      expect(mac1).to_not eq(mac2)
    end

    context "when the source container has applied profiles" do

      it "copies the profiles", :container, :profiles, :delete_copy do
        container = client.container("test-container")
        response = client.update_container("test-container",
          container.to_hash.merge(profiles: %w[test-profile1 test-profile2]))
        client.wait_for_operation(response.id)

        response = client.copy_container("test-container", "test-container2")
        client.wait_for_operation(response.id)

        container = client.container("test-container2")
        expect(container.profiles).to eq(%w[test-profile1 test-profile2])
      end

    end

    it "copies the source container's configuration", :container, :delete_copy do
      container = client.container("test-container").to_hash
      config = container[:config]

      response = client.update_container("test-container",
        container.merge(config: config.merge("raw.lxc" => "lxc.aa_profile=unconfined")))

      response = client.copy_container("test-container", "test-container2")
      client.wait_for_operation(response.id)

      container = client.container("test-container2")
      expect(container.config["raw.lxc"]).to eq("lxc.aa_profile=unconfined")
    end

    context "when the source container is ephemeral", :container, :delete_copy do

      it "creates a persistent target container" do
        container = client.container("test-container").to_hash

        response = client.update_container("test-container",
          container.to_hash.merge(ephemeral: true))

        container = client.container("test-container")
        expect(container).to be_ephemeral

        response = client.copy_container("test-container", "test-container2")
        client.wait_for_operation(response.id)

        container = client.container("test-container2")
        expect(container).to_not be_ephemeral
      end

    end

    context "when an architecture is specified" do

      it "passes on the architecture" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test2",
            architecture: "i686",
            source: { type: "copy", source: "test" }
          })).
          to_return(ok_response)

        client.copy_container("test", "test2", architecture: "i686")

        assert_requested request
      end

    end

    context "when a list of profiles is specified" do

      it "passes on the profiles" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test2",
            profiles: ['test1', 'test2'],
            source: { type: "copy", source: "test" }
          })).
          to_return(ok_response)

        client.copy_container("test", "test2", profiles: %w[test1 test2])

        assert_requested request
      end

      it "overrides any profiles applied to the source container", :container, :profiles, :delete_copy do

        container1 = client.container("test-container")

        response = client.copy_container("test-container",
          "test-container2",
          profiles: %w[test-profile1 test-profile2])
        client.wait_for_operation(response.id)

        container2 = client.container("test-container2")

        expect(container1.profiles).to eq(%w[default])
        expect(container2.profiles).to eq(%w[test-profile1 test-profile2])
      end

    end

    context "when 'ephemeral: true' is specified" do

      it "passes it along" do

        request = stub_post("/1.0/containers").
          with(body: hash_including({
            name: "test2",
            ephemeral: true,
            source: { type: "copy", source: "test" }
          })).
          to_return(ok_response)

        client.copy_container("test", "test2", ephemeral: true)

        assert_requested request
      end

      it "makes the container ephemeral", :container, :delete_copy do
        response = client.copy_container("test-container",
          "test-container2",
          ephemeral: true)
        client.wait_for_operation(response.id)

        container1 = client.container("test-container")
        container2 = client.container("test-container2")

        expect(container1).to_not be_ephemeral
        expect(container2).to be_ephemeral
      end

    end

    context "when 'ephemeral: true' is not specified", :container, :delete_copy do

      it "defaults to a persistent container" do
        response = client.copy_container("test-container", "test-container2")
        client.wait_for_operation(response.id)

        container1 = client.container("test-container")
        container2 = client.container("test-container2")

        expect(container1).to_not be_ephemeral
        expect(container2).to_not be_ephemeral
      end

    end

    context "when a config hash is specified" do

      it "passes on the configuration" do
        request = stub_post("/1.0/containers").
          with(body: hash_including({
              name: "test2",
              config: { hello: "world" },
              source: { type: "copy", source: "test" }
          })).
          to_return(ok_response)

        client.copy_container("test", "test2",
          config: { hello: "world" })

        assert_requested request
      end

      it "stores the configuration with the container", :container, :delete_copy do
        response = client.copy_container("test-container",
          "test-container2",
          config: { "volatile.eth0.hwaddr" => "aa:bb:cc:dd:ee:ff" })
        client.wait_for_operation(response.id)

        container = client.container("test-container2")
        expect(container.config["volatile.eth0.hwaddr"]).to eq("aa:bb:cc:dd:ee:ff")
      end

      it "accepts non-String values", :container, :delete_copy do

        client.copy_container("test-container",
          "test-container2",
          config: { "limits.cpu" => 2 })

        container = client.container("test-container2")
        expect(container.config["limits.cpu"]).to eq("2")

      end

    end

  end

  describe ".container_snapshots", :vcr do

    it "returns an array of snapshots for a container", :container do
      snapshots = client.container_snapshots("test-container")
      expect(snapshots).to be_kind_of(Array)
    end

    it "makes the correct API call" do
      request = stub_get("/1.0/containers/test/snapshots").
        to_return(ok_response.merge(body: { metadata: [] }.to_json))

      snapshots = client.container_snapshots("test")
      assert_requested request
    end

    it "returns only the image names and not their paths" do

      body = { metadata: [
        "/1.0/containers/test/snapshots/test1",
        "/1.0/containers/test/snapshots/test2",
        "/1.0/containers/test/snapshots/test3",
        "/1.0/containers/test/snapshots/test4"
      ]}.to_json

      stub_get("/1.0/containers/test/snapshots").
        to_return(ok_response.merge(body: body))

      snapshots = client.container_snapshots("test")
      expect(snapshots).to eq(%w[test1 test2 test3 test4])
    end

  end

end
