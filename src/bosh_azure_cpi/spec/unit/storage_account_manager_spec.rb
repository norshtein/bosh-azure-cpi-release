require 'spec_helper'

describe Bosh::AzureCloud::StorageAccountManager do
  let(:azure_properties) { mock_azure_properties }
  let(:blob_manager) { instance_double(Bosh::AzureCloud::BlobManager) }
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager) }
  let(:client2) { instance_double(Bosh::AzureCloud::AzureClient2) }
  let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_properties, blob_manager, disk_manager, client2) }
  let(:azure_client) { instance_double(Azure::Storage::Client) }
  let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }

  before do
    allow(Azure::Storage::Client).to receive(:create).
      and_return(azure_client)
    allow(azure_client).to receive(:storage_table_host)
  end

  describe "#generate_storage_account_name" do
    context "when the first generated name is available" do
      let(:storage_account_name) { "386ebba59c883c7d15b419b3" }
      before do
        allow(SecureRandom).to receive(:hex).with(12).and_return(storage_account_name)
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name).
          and_return({
            :available => true
          })
      end

      it "should return the available storage account name" do
        expect(client2).to receive(:check_storage_account_name_availability).once
        expect(storage_account_manager.generate_storage_account_name()).to eq(storage_account_name)
      end
    end

    context "when the first generated name is not available, and the second one is available" do
      let(:storage_account_name_unavailable) { "386ebba59c883c7d15b419b3" }
      let(:storage_account_name_available)   { "db49daf2fbbf100575a3af9c" }
      before do
        allow(SecureRandom).to receive(:hex).with(12).and_return(storage_account_name_unavailable, storage_account_name_available)
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name_unavailable).
          and_return({
            :available => false
          })
        allow(client2).to receive(:check_storage_account_name_availability).with(storage_account_name_available).
          and_return({
            :available => true
          })
      end

      it "should return the available storage account name" do
        expect(client2).to receive(:check_storage_account_name_availability).twice
        expect(storage_account_manager.generate_storage_account_name()).to eq(storage_account_name_available)
      end
    end
  end

  describe '#create_storage_account' do
    # Parameters
    let(:name) { "fake-storage-account-name" }
    let(:location) { "fake-storage-account-location" }
    let(:type) { "fake-storage-account-type" }
    let(:tags) { {"foo" => "bar"} }
    let(:containers) { ['bosh', 'stemcell'] }
    let(:is_default_storage_account) { false }

    let(:storage_account) { double('storage-account') }
    let(:lock_creating_storage_account) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }

    before do
      allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).and_return(lock_creating_storage_account)
    end

    context 'when lock is not acquired' do
      before do
        allow(lock_creating_storage_account).to receive(:lock).and_return(false)
      end

      it 'should wait and return the storage account if the storage account is created by other process' do
        expect(lock_creating_storage_account).to receive(:wait)
        expect(storage_account_manager).to receive(:find_storage_account_by_name).
          and_return(storage_account)
        expect(
          storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
        ).to be(storage_account)
      end

      it 'should raise error if the storage account is not created by other process' do
        expect(lock_creating_storage_account).to receive(:wait)
        expect(storage_account_manager).to receive(:find_storage_account_by_name).
          and_return(nil)
        expect{
          storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
        }.to raise_error("Storage account `#{name}' is not created.")
      end

      it 'should raise error if error happens' do
        expect(lock_creating_storage_account).to receive(:wait).
          and_raise('timeout')
        expect{
          storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
        }.to raise_error(/Failed to create storage account in location `#{location}' with name `#{name}' and tags `#{tags}'/)
      end
    end

    context 'when lock is acquired' do
      before do
        allow(lock_creating_storage_account).to receive(:lock).and_return(true)
        allow(lock_creating_storage_account).to receive(:unlock)
      end

      context 'when the storage account is already created by other process' do
        before do
          expect(storage_account_manager).to receive(:find_storage_account_by_name).
            and_return(storage_account)
        end

        it 'should return the storage account directly' do
          expect(
            storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
          ).to be(storage_account)
        end
      end

      context 'if the storage account is going to be created' do
        context 'when the storage account name is invalid' do
          let(:result) {
            {
              :available => false,
              :reason => 'AccountNameInvalid',
              :message => 'fake-message'
            }
          }
          before do
            allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
            allow(client2).to receive(:check_storage_account_name_availability).with(name).and_return(result)
          end

          it 'should raise an error' do
            expect {
              storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
            }.to raise_error(/The storage account name `#{name}' is invalid./)
          end
        end

        context 'when the storage account is not available' do
          let(:result) {
            {
              :available => false,
              :reason => 'fake-reason',
              :message => 'fake-message'
            }
          }
          before do
            allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
            allow(client2).to receive(:check_storage_account_name_availability).with(name).and_return(result)
          end

          it 'should raise an error' do
            expect {
              storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
            }.to raise_error(/The storage account with the name `#{name}' is not available/)
          end
        end

        context 'when everything is ok' do
          let(:result) { {:available => true} }

          before do
            allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil, storage_account)
            allow(client2).to receive(:check_storage_account_name_availability).with(name).and_return(result)
          end

          it 'should create the storage account and prepare the containers' do
            expect(blob_manager).to receive(:prepare_containers).
              with(name, containers, is_default_storage_account)
            expect(client2).to receive(:create_storage_account).
              with(name, location, type, tags)
            expect(
              storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
            ).to be(storage_account)
          end
        end

        context 'when it fails to prepare containers' do
          let(:result) { {:available => true} }

          before do
            allow(storage_account_manager).to receive(:find_storage_account_by_name).and_return(nil)
            allow(client2).to receive(:check_storage_account_name_availability).with(name).and_return(result)
            allow(client2).to receive(:create_storage_account).
              with(name, location, type, tags).
              and_return(true)
            expect(blob_manager).to receive(:prepare_containers).
              with(name, containers, is_default_storage_account).
              and_raise('failed to create')
          end

          it 'should create the storage account and prepare the containers' do
            expect {
              storage_account_manager.create_storage_account(name, tags, type, location, containers, is_default_storage_account)
            }.to raise_error(/it failed to prepare the containers/)
          end
        end
      end
    end
  end

  describe '#create_storage_account_by_tags' do
    let(:tags) { { 'key' => 'value' } }
    let(:type) { 'fake-type' }
    let(:location) { 'fake-location' }
    let(:containers) { ['bosh'] }
    let(:is_default_storage_account) { false }

    let(:lock) { instance_double(Bosh::AzureCloud::Helpers::FileMutex) }
    let(:lock_file) { "bosh-lock-create-storage-account-#{location}-#{Digest::MD5.hexdigest(tags.to_s)}" }

    let(:storage_account) { {:name => 'fake-name'} }

    before do
      allow(Bosh::AzureCloud::Helpers::FileMutex).to receive(:new).
        with(lock_file, anything).
        and_return(lock)
    end

    context 'when lock is acquired' do
      before do
        allow(lock).to receive(:lock).and_return(true)
        allow(lock).to receive(:unlock)
      end

      context 'when the storage account is already created' do
        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_tags).
            with(tags, location).
            and_return(storage_account)
        end

        it 'should return the storage account directly' do
          expect(
            storage_account_manager.create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
          ).to be(storage_account)
        end
      end

      context 'when the storage account does not exist' do
        let(:name) { 'fake-name' }

        before do
          allow(storage_account_manager).to receive(:generate_storage_account_name).
            and_return(name)
          allow(storage_account_manager).to receive(:find_storage_account_by_tags).
            with(tags, location).
            and_return(nil)
        end

        it 'should create a new storage account' do
          expect(storage_account_manager).to receive(:create_storage_account).
            with(name, tags, type, location, containers, is_default_storage_account).
            and_return(storage_account)
          expect(
            storage_account_manager.create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
          ).to be(storage_account)
        end
      end

      context 'when the storage account does not exist and get error when creating a new one' do
        let(:name) { 'fake-name' }

        before do
          allow(storage_account_manager).to receive(:generate_storage_account_name).
            and_return(name)
          allow(storage_account_manager).to receive(:find_storage_account_by_tags).
            with(tags, location).
            and_return(nil)
        end

        it 'should raise an error' do
          expect(storage_account_manager).to receive(:create_storage_account).
            with(name, tags, type, location, containers, is_default_storage_account).
            and_raise('failed to create')
          expect{
            storage_account_manager.create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
          }.to raise_error(/Failed to create storage account in location `#{location}' with tags `#{tags}'/)
        end
      end
    end

    context 'when lock is not acquired' do
      let(:storage_account) { {:name => 'fake-name'} }

      before do
        allow(lock).to receive(:lock).and_return(false)
      end

      it 'should wait and then find the storage account' do
        expect(lock).to receive(:wait)
        expect(storage_account_manager).to receive(:find_storage_account_by_tags).
          with(tags, location).
          and_return(storage_account)
        expect(
          storage_account_manager.create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
        ).to be(storage_account)
      end
    end

    context 'when storage account is not created' do
      before do
        allow(lock).to receive(:lock).and_return(false)
      end

      it 'should raise an error' do
        expect(lock).to receive(:wait)
        expect(storage_account_manager).to receive(:find_storage_account_by_tags).
          with(tags, location).
          and_return(nil)
        expect{
          storage_account_manager.create_storage_account_by_tags(tags, type, location, containers, is_default_storage_account)
        }.to raise_error(/Storage account for tags `#{tags}' is not created./)
      end
    end
  end

  describe '#find_storage_account_by_name' do
    context 'when storage account exists' do
      let(:name) { 'fake-name' }
      let(:storage_account) { {:name => 'fake-name'} }

      it 'get the storage account by name' do
        expect(client2).to receive(:get_storage_account_by_name).
          with(name).
          and_return(storage_account)
        expect(
          storage_account_manager.find_storage_account_by_name(name)
        ).to be(storage_account)
      end
    end

    context 'when storage account does not exist' do
      let(:name) { 'fake-name' }

      before do
        allow(client2).to receive(:get_storage_account_by_name).with(name).and_return(nil)
      end

      it 'should return nil' do
        expect(
          storage_account_manager.find_storage_account_by_name(name)
        ).to be(nil)
      end
    end
  end

  describe '#find_storage_account_by_tags' do
    let(:tags) { {'key' => 'value'} }
    let(:location) { 'fake-location' }

    context 'when storage account exists' do
      let(:name) { 'fake-name' }
      let(:storage_account) {
        {
          :name => name,
          :location => location,
          :tags => tags
        }
      }

      before do
        allow(client2).to receive(:list_storage_accounts).
          and_return([storage_account])
      end

      it 'should return the storage account' do
        expect(
          storage_account_manager.find_storage_account_by_tags(tags, location)
        ).to be(storage_account)
      end
    end

    context 'when storage account does not exist' do
      let(:name) { 'fake-name' }
      let(:storage_account) {
        {
          :name => name,
          :location => location,
          :tags => { 'x' => 'y' }
        }
      }

      before do
        allow(client2).to receive(:list_storage_accounts).
          and_return([storage_account])
      end

      it 'should return nil' do
        expect(
          storage_account_manager.find_storage_account_by_tags(tags, location)
        ).to be(nil)
      end
    end
  end

  describe '#get_storage_account_from_resource_pool' do
    let(:location) { 'fake-location' }
    let(:default_storage_account) {
      {
        :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    }
    before do
      allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    let(:storage_account_name) { 'fake-storage-account-name-in-resource-pool' }
    let(:storage_account) {
      {
        :name => storage_account_name
      }
    }

    context 'when resource_pool does not contain storage_account_name' do
      let(:resource_pool) {
        {
          'instance_type' => 'fake-vm-size'
        }
      }

      it 'should return the default storage account' do
        storage_account_manager.default_storage_account_name()

        expect(
          storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
        ).to be(default_storage_account)
      end
    end

    context 'when resource_pool contains storage_account_name' do
      context 'when the storage account name is not a pattern' do
        let(:resource_pool) {
          {
            'instance_type' => 'fake-vm-size',
            'storage_account_name' => storage_account_name
          }
        }

        context 'when the storage account exists' do
          before do
            allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(storage_account)
          end

          it 'should return the existing storage account' do
            expect(
              storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
            ).to be(storage_account)
          end
        end

        context 'when the storage account does not exist' do
          context 'when resource_pool does not contain storage_account_type' do
            before do
              allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(nil)
            end

            it 'should raise an error' do
              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              }.to raise_error(/missing required cloud property `storage_account_type'/)
            end
          end

          context 'when resource_pool contains storage_account_type' do
            let(:storage_account_type) { "Standard_LRS" }
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => storage_account_name,
                'storage_account_type' => storage_account_type
              }
            }
            before do
              allow(client2).to receive(:get_storage_account_by_name).with(storage_account_name).and_return(nil, storage_account)
            end

            it 'should create the storage account' do
              expect(storage_account_manager).to receive(:create_storage_account).
                with(storage_account_name, {}, storage_account_type, location, ['bosh', 'stemcell'], false)
              expect(
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              ).to be(storage_account)
            end
          end
        end
      end

      context 'when the storage account name is a pattern' do
        context 'when the pattern is valid' do
          let(:resource_pool) {
            {
              'instance_type' => 'fake-vm-size',
              'storage_account_name' => '*pattern*'
            }
          }
          let(:storage_accounts) {
            [
              {
                :name => 'pattern',
                :location => 'fake-location'
              }, {
                :name => '2pattern',
                :location => 'fake-location'
              }, {
                :name => 'pattern3',
                :location => 'fake-location'
              }, {
                :name => '4pattern4',
                :location => 'fake-location'
              }, {
                :name => 'tpattern',
                :location => 'fake-location'
              }, {
                :name => 'patternt',
                :location => 'fake-location'
              }, {
                :name => 'tpatternt',
                :location => 'fake-location'
              }, {
                :name => 'patten',
                :location => 'fake-location'
              }, {
                :name => 'foo',
                :location => 'fake-location'
              }
            ]
          }

          context 'when finding an availiable storage account successfully' do
            let(:disks) {
              [
                1,2,3
              ]
            }

            before do
              allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            end

            context 'without storage_account_max_disk_number' do
              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should not raise any error' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              end
            end

            context 'with 2 as storage_account_max_disk_number' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern*',
                  'storage_account_max_disk_number' => 2
                }
              }

              before do
                allow(disk_manager).to receive(:list_disks).and_return(disks)
                allow(disk_manager).to receive(:list_disks).with('4pattern4').and_return([])
              end

              it 'should return an available storage account whose disk number is smaller than storage_account_max_disk_number' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).to receive(:list_disks).with(/pattern/)
                expect(disk_manager).not_to receive(:list_disks).with('patten')
                expect(disk_manager).not_to receive(:list_disks).with('foo')

                expect(
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
                ).to eq(
                  {
                    :name => '4pattern4',
                    :location => 'fake-location'
                  }
                )
              end
            end
          end

          context 'when cannot find an availiable storage account' do
            context 'when cannot find a storage account by the pattern' do
              let(:storage_accounts) { [] }

              before do
                allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              end

              it 'should raise an error' do
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
                }.to raise_error(/get_storage_account_from_resource_pool - Cannot find an available storage account./)
              end
            end

            context 'when the disk number of every storage account is more than the limitation' do
              let(:disks) { (1..31).to_a }

              before do
                allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
                allow(disk_manager).to receive(:list_disks).and_return(disks)
              end

              it 'should raise an error' do
                expect(client2).not_to receive(:create_storage_account)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
                }.to raise_error(/get_storage_account_from_resource_pool - Cannot find an available storage account./)
              end
            end
          end
        end

        context 'when the pattern is invalid' do
          context 'when the pattern contains one asterisk' do
            context 'when the pattern starts with one asterisk' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => '*pattern'
                }
              }

              it 'should raise an error' do
                expect(client2).not_to receive(:list_storage_accounts)
                expect(client2).not_to receive(:create_storage_account)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
                }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
              end
            end

            context 'when the pattern ends with one asterisk' do
              let(:resource_pool) {
                {
                  'instance_type' => 'fake-vm-size',
                  'storage_account_name' => 'pattern*'
                }
              }

              it 'should raise an error' do
                expect(client2).not_to receive(:list_storage_accounts)
                expect(client2).not_to receive(:create_storage_account)
                expect(client2).not_to receive(:get_storage_account_by_name)
                expect(disk_manager).not_to receive(:list_disks)

                expect {
                  storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
                }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
              end
            end
          end

          context 'when the pattern contains more than two asterisks' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '**pattern*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end

          context 'when the pattern contains upper-case letters' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*PATTERN*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end

          context 'when the pattern contains special characters' do
            let(:resource_pool) {
              {
                'instance_type' => 'fake-vm-size',
                'storage_account_name' => '*pat+tern*'
              }
            }

            it 'should raise an error' do
              expect(client2).not_to receive(:list_storage_accounts)
              expect(client2).not_to receive(:create_storage_account)
              expect(client2).not_to receive(:get_storage_account_by_name)
              expect(disk_manager).not_to receive(:list_disks)

              expect {
                storage_account_manager.get_storage_account_from_resource_pool(resource_pool, location)
              }.to raise_error(/get_storage_account_from_resource_pool - storage_account_name in resource_pool is invalid./)
            end
          end
        end
      end
    end
  end

  describe '#default_storage_account' do
    let(:default_storage_account) {
      {
        :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME
      }
    }
    before do
      allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
    end

    context 'When the global configurations contain storage_account_name' do
      context 'When use_managed_disks is false' do
        it 'should return the default storage account, and do not set the tags' do
          expect(client2).not_to receive(:update_tags_of_storage_account)
          expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
        end
      end

      context 'When use_managed_disks is true' do
        let(:azure_properties_managed) {
          mock_azure_properties_merge({
            'use_managed_disks' => true
          })
        }
        let(:storage_account_manager) { Bosh::AzureCloud::StorageAccountManager.new(azure_properties_managed, blob_manager, disk_manager, client2) }

        context 'When the default storage account do not have the tags' do
          it 'should return the default storage account, and set the tags' do
            expect(client2).to receive(:update_tags_of_storage_account).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME, STEMCELL_STORAGE_ACCOUNT_TAGS)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end

        context 'When the default storage account has the tags' do
          let(:default_storage_account) {
            {
              :name => MOCK_DEFAULT_STORAGE_ACCOUNT_NAME,
              :tags => STEMCELL_STORAGE_ACCOUNT_TAGS
            }
          }
          before do
            allow(client2).to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME).and_return(default_storage_account)
          end

          it 'should return the default storage account, and do not set the tags' do
            expect(client2).not_to receive(:update_tags_of_storage_account)
            expect(storage_account_manager.default_storage_account).to eq(default_storage_account)
          end
        end
      end
    end

    context 'When the global configurations do not contain storage_account_name' do
      let(:tags) {
        {
          'user-agent' => 'bosh',
          'type' => 'stemcell'
        }
      }
      let(:resource_group_location) { 'fake-resource-group-location' }
      let(:resource_group) {
        {
          :name => "fake-rg-name",
          :location => resource_group_location
        }
      }

      context 'When the storage account with the specified tags is found in the resource group location' do
        let(:targeted_storage_account) {
          {
            :name => 'account1',
            :location => resource_group_location,
            :tags => tags
          }
        }
        let(:storage_accounts) {
          [
            targeted_storage_account,
            {
              :name => 'account2',
              :location => resource_group_location,
              :tags => {}
            },
            {
              :name => 'account3',
              :location => 'different-location',
              :tags => tags
            }
          ]
        }
        before do
          allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
          allow(client2).to receive(:get_resource_group).
            with(default_resource_group_name).
            and_return(resource_group)
        end

        it 'should return the storage account' do
          azure_properties.delete('storage_account_name')
          expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)

          expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
        end
      end

      context 'When the storage account with the specified tags is not found in the resource group location' do
        let(:request_id) { 'fake-client-request-id' }
        let(:options) {
          {
            :request_id => request_id
          }
        }
        let(:azure_client) { instance_double(Azure::Storage::Client) }
        let(:table_service) { instance_double(Azure::Storage::Table::TableService) }
        let(:exponential_retry) { instance_double(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter) }
        let(:storage_dns_suffix) { "fake-storage-dns-suffix" }

        before do
          allow(azure_client).to receive(:table_client).
            and_return(table_service)
          allow(Azure::Storage::Core::Filter::ExponentialRetryPolicyFilter).to receive(:new).
            and_return(exponential_retry)
          allow(table_service).to receive(:with_filter).with(exponential_retry)
          allow(SecureRandom).to receive(:uuid).and_return(request_id)
        end

        context 'When the old storage account with the stemcell table is found in the resource group' do
          before do
            allow(table_service).to receive(:get_table).
              with('stemcells', options)
          end

          context 'When the old storage account is in the resource group location' do
            let(:targeted_storage_account) {
              {
                :name => 'account1',
                :location => resource_group_location,
                :account_type => 'Standard_LRS',
                :storage_blob_host => "https://account1.blob.#{storage_dns_suffix}",
                :storage_table_host => "https://account1.table.#{storage_dns_suffix}"
              }
            }
            let(:storage_accounts) {
              [
                targeted_storage_account
              ]
            }
            let(:keys) { ['fake-key-1', 'fake-key-2'] }

            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(client2).to receive(:get_resource_group).
                with(default_resource_group_name).
                and_return(resource_group)
              allow(client2).to receive(:get_storage_account_by_name).
                with(targeted_storage_account[:name]).
                and_return(targeted_storage_account)
              allow(client2).to receive(:get_storage_account_keys_by_name).
                with(targeted_storage_account[:name]).
                and_return(keys)
            end

            it 'should return the storage account' do
              azure_properties.delete('storage_account_name')
              expect(Azure::Storage::Client).to receive(:create).
                with({
                  :storage_account_name => targeted_storage_account[:name],
                  :storage_access_key   => keys[0],
                  :storage_dns_suffix   => storage_dns_suffix,
                  :user_agent_prefix    => "BOSH-AZURE-CPI"
                }).and_return(azure_client)
              expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
              expect(client2).to receive(:update_tags_of_storage_account).with(targeted_storage_account[:name], tags)

              expect(storage_account_manager.default_storage_account).to eq(targeted_storage_account)
            end
          end

          context 'When the old storage account is not in the resource group location' do
            let(:targeted_storage_account) {
              {
                :name => 'account1',
                :location => 'another-resource-group-location',
                :account_type => 'Standard_LRS',
                :storage_blob_host => "https://account1.blob.#{storage_dns_suffix}",
                :storage_table_host => "https://account1.table.#{storage_dns_suffix}"
              }
            }
            let(:storage_accounts) {
              [
                targeted_storage_account
              ]
            }
            let(:keys) { ['fake-key-1', 'fake-key-2'] }

            before do
              allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
              allow(client2).to receive(:get_resource_group).
                with(default_resource_group_name).
                and_return(resource_group)
              allow(client2).to receive(:get_storage_account_by_name).
                with(targeted_storage_account[:name]).
                and_return(targeted_storage_account)
              allow(client2).to receive(:get_storage_account_keys_by_name).
                with(targeted_storage_account[:name]).
                and_return(keys)
            end

            it 'should raise an error' do
              azure_properties.delete('storage_account_name')
              expect(Azure::Storage::Client).to receive(:create).
                with({
                  :storage_account_name => targeted_storage_account[:name],
                  :storage_access_key   => keys[0],
                  :storage_dns_suffix   => storage_dns_suffix,
                  :user_agent_prefix    => "BOSH-AZURE-CPI"
                }).and_return(azure_client)

              expect {
                storage_account_manager.default_storage_account
              }.to raise_error(/The existing default storage account `#{targeted_storage_account[:name]}' has a different location other than the resource group location./)
            end
          end
        end

        context 'When no standard storage account is found in the resource group' do
          let(:targeted_storage_account) {
            {
              :name => 'account1',
              :location => resource_group_location,
              :account_type => 'Premium_LRS',
              :storage_blob_host => "https://account1.blob.#{storage_dns_suffix}",
              :storage_table_host => "https://account1.table.#{storage_dns_suffix}"
            }
          }
          let(:storage_accounts) {
            [
              targeted_storage_account
            ]
          }

          before do
            allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(client2).to receive(:get_resource_group).
              with(default_resource_group_name).
              and_return(resource_group)
            allow(client2).to receive(:get_storage_account_by_name).
              with(targeted_storage_account[:name]).
              and_return(targeted_storage_account)
          end

          it 'should create a new storage account' do
            azure_properties.delete('storage_account_name')
            expect(client2).not_to receive(:get_storage_account_by_name).with(MOCK_DEFAULT_STORAGE_ACCOUNT_NAME)
            expect(storage_account_manager).to receive(:create_storage_account_by_tags).
              with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', resource_group_location, ['bosh', 'stemcell'], true).
              and_return(targeted_storage_account)

            storage_account_manager.default_storage_account
          end
        end

        context 'When the old storage account with the stemcell table is not found in the resource group' do
          let(:targeted_storage_account) {
            {
              :name => 'account1',
              :location => resource_group_location,
              :account_type => 'Standard_LRS',
              :storage_blob_host => "https://account1.blob.#{storage_dns_suffix}",
              :storage_table_host => "https://account1.table.#{storage_dns_suffix}"
            }
          }
          let(:storage_accounts) {
            [
              targeted_storage_account
            ]
          }
          let(:keys) { ['fake-key-1', 'fake-key-2'] }

          before do
            allow(client2).to receive(:list_storage_accounts).and_return(storage_accounts)
            allow(client2).to receive(:get_resource_group).
              with(default_resource_group_name).
              and_return(resource_group)
            allow(client2).to receive(:get_storage_account_by_name).
              with(targeted_storage_account[:name]).
              and_return(targeted_storage_account)
            allow(client2).to receive(:get_storage_account_keys_by_name).
              with(targeted_storage_account[:name]).
              and_return(keys)
            allow(table_service).to receive(:get_table).
              and_raise("(404)") # The table stemcells is not found in the storage account
          end

          it 'should create a new storage account' do
            azure_properties.delete('storage_account_name')
            expect(storage_account_manager).to receive(:create_storage_account_by_tags).
              with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', resource_group_location, ['bosh', 'stemcell'], true).
              and_return(targeted_storage_account)

            storage_account_manager.default_storage_account
          end
        end
      end

      context 'When no storage account is found in the resource group location' do
        let(:targeted_storage_account) { {:name => 'account1'} }
        before do
          allow(client2).to receive(:list_storage_accounts).and_return([])
          allow(client2).to receive(:get_resource_group).
            with(default_resource_group_name).
            and_return(resource_group)
        end

        it 'should create a new storage account' do
          azure_properties.delete('storage_account_name')
          expect(storage_account_manager).to receive(:create_storage_account_by_tags).
            with(STEMCELL_STORAGE_ACCOUNT_TAGS, 'Standard_LRS', resource_group_location, ['bosh', 'stemcell'], true).
            and_return(targeted_storage_account)

          storage_account_manager.default_storage_account
        end
      end
    end

    describe '#get_or_create_diagnostics_storage_account' do
      let(:diagnostic_tags) {
        {
          'user-agent' => 'bosh',
          'type' => 'bootdiagnostics'
        }
      }
      let(:location) { 'fake-location' }
      let(:storage_account) { double('storage-account') }

      context 'when the diagnostics storage account exists' do
        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_tags).
            with(diagnostic_tags, location).
            and_return(storage_account)
        end

        it 'should return the storage account directly' do
          expect(
            storage_account_manager.get_or_create_diagnostics_storage_account(location)
          ).to be(storage_account)
        end
      end

      context 'when the diagnostics storage account does not exist' do
        before do
          allow(storage_account_manager).to receive(:find_storage_account_by_tags).
            with(diagnostic_tags, location).
            and_return(nil)
        end

        it 'should create the storage account' do
          expect(storage_account_manager).to receive(:create_storage_account_by_tags).
            with(diagnostic_tags, 'Standard_LRS', location, [], false).
            and_return(storage_account)
          expect(
            storage_account_manager.get_or_create_diagnostics_storage_account(location)
          ).to be(storage_account)
        end
      end

    end
  end
end
