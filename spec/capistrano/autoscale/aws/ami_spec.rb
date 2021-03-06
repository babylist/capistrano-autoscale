# frozen_string_literal: true

describe Capistrano::Autoscale::AWS::AMI do
  subject { Capistrano::Autoscale::AWS::AMI.new 'test' }

  describe '#initialize' do
    it 'sets the id' do
      expect(subject.id).to eq 'test'
    end

    it 'has an aws-sdk counterpart' do
      expect(subject.aws_counterpart).to be_a_kind_of ::Aws::EC2::Image
      expect(subject.aws_counterpart.id).to eq 'test'
    end

    context 'with snapshots' do
      subject do
        Capistrano::Autoscale::AWS::AMI.new 'test', [
          double(:bdm, ebs: double(:ebs, snapshot_id: 'snap-1'))
        ]
      end

      it 'sets snapshots to Snapshot objects' do
        expect(subject.snapshots.size).to eq 1
        expect(subject.snapshots[0]).to be_a_kind_of Capistrano::Autoscale::AWS::Snapshot
      end

      it 'sets the ID on the Snapshots' do
        expect(subject.snapshots[0].id).to eq 'snap-1'
      end
    end
  end

  describe '#deploy_group' do
    it 'returns the Autoscale-Deploy-group tag, if set' do
      webmock :post, /ec2/ => 201, with: Hash[body: /Action=CreateTags/]
      subject.tag 'Autoscale-Deploy-group', 'test'
      expect(subject.deploy_group).to eq 'test'
    end

    it 'returns nil if the tag was never set' do
      webmock :post, %r{ec2.(.*).amazonaws.com\/\z} => 'DescribeImages.200.xml',
        with: Hash[body: /Action=DescribeImages/]
      expect(subject.deploy_group).to be_nil
    end
  end

  describe '#delete' do
    before do
      webmock :post, /ec2/ => 201, with: Hash[body: /Action=DeregisterImage/]
    end

    it 'calls the deregister AMI API' do
      subject.delete
      expect(WebMock)
        .to have_requested(:post, /ec2/)
        .with body: /Action=DeregisterImage&ImageId=test/
    end

    context 'with snapshots' do
      subject do
        Capistrano::Autoscale::AWS::AMI.new 'test', [
          double(:bdm, ebs: double(:ebs, snapshot_id: 'snap-1'))
        ]
      end

      it 'deletes the AMIs snapshots too' do
        webmock :post, /ec2/ => 201, with: Hash[body: /Action=DeleteSnapshot/]

        subject.delete
        expect(WebMock)
          .to have_requested(:post, /ec2/)
          .with body: /Action=DeleteSnapshot&SnapshotId=snap-1/
      end
    end
  end

  describe '.create' do
    subject { described_class }
    let(:instance) { Capistrano::Autoscale::AWS::Instance.new 'i-1234567890', nil, nil }

    before do
      webmock :post, %r{ec2.(.*).amazonaws.com\/\z} => 'CreateImage.200.xml',
        with: Hash[body: /Action=CreateImage/]

      webmock :post, %r{ec2.(.*).amazonaws.com\/\z} => 'DescribeImages.200.xml',
        with: Hash[body: /Action=DescribeImages/]

      webmock :post, %r{amazonaws.com\/\z} => 'CreateTags.200.xml',
        with: Hash[body: /Action=CreateTags/]
    end

    it 'calls the API with the instance given' do
      subject.create instance
      expect(WebMock)
        .to have_requested(:post, /ec2/)
        .with body: /Action=CreateImage&InstanceId=i-1234567890&Name=autoscale-(\d+)/
    end

    it 'sets the no_reboot option to false by default' do
      subject.create instance
      expect(WebMock)
        .to have_requested(:post, /ec2/)
        .with(body: /NoReboot=false/)
    end

    it 'sets the no_reboot options to true, if given' do
      subject.create instance, no_reboot: true
      expect(WebMock)
        .to have_requested(:post, /ec2/)
        .with(body: /NoReboot=true/)
    end

    it 'returns the an AMI object with the new id' do
      ami = subject.create instance
      expect(ami.id).to eq 'ami-4fa54026' # from stub
    end
  end
end
