require 'spec_helper'
require 'grocer/connection'

describe Grocer::Connection do
  subject { described_class.new(connection_options) }
  let(:connection_options) { { certificate: '/path/to/cert.pem',
                               gateway: 'push.example.com',
                               port: 443 } }
  let(:ssl) { stub('SSLConnection', connect: nil, new: nil, write: nil, read: nil, close: nil) }
  before do
    Grocer::SSLConnection.stubs(:new).returns(ssl)
  end

  it 'defaults to 3 retries' do
    expect(subject.retries).to eq(3)
  end

  it 'can be initialized with a number of retries' do
    connection_options[:retries] = 2
    expect(subject.retries).to eq(2)
  end

  it 'can open the connection to the apple push notification service' do
    subject.connect
    ssl.should have_received(:connect)
  end

  it 'raises CertificateExpiredError for OpenSSL::SSL::SSLError with /certificate expired/i message' do
    ssl.stubs(:write).raises(OpenSSL::SSL::SSLError.new('certificate expired'))
    -> {subject.write('abc123')}.should raise_error(Grocer::CertificateExpiredError)
  end

  context 'an open SSLConnection' do
    before do
      ssl.stubs(:connected?).returns(true)
    end

    it '#write delegates to open SSLConnection' do
      subject.write('Apples to Oranges')
      ssl.should have_received(:write).with('Apples to Oranges')
    end

    it '#read delegates to open SSLConnection' do
      subject.read(42, 'IO')
      ssl.should have_received(:read).with(42, 'IO')
    end

    it '#read_with_timeout delegates to open SSLConnection' do
      ssl.expects(:read_with_timeout).with(42)
      subject.read_with_timeout(42)
    end

    it "#close delegates to ssl connection" do
      subject.close
      ssl.should have_received(:close)
    end
  end

  context 'a closed SSLConnection' do
    before do
      ssl.stubs(:connected?).returns(false)
    end

    it '#write connects SSLConnection and delegates to it' do
      subject.write('Apples to Oranges')
      ssl.should have_received(:connect)
      ssl.should have_received(:write).with('Apples to Oranges')
    end

    it '#read connects SSLConnection delegates to open SSLConnection' do
      subject.read(42, 'IO')
      ssl.should have_received(:connect)
      ssl.should have_received(:read).with(42, 'IO')
    end

    it '#read_if_connected doesnt connect a closed connection' do
      ssl.expects(:read_with_timeout)
      subject.read_with_timeout(42)
      ssl.should have_received(:connect).never
    end
  end

  describe 'retries' do
    [SocketError, OpenSSL::SSL::SSLError, Errno::EPIPE].each do |error|
      it "retries #read in the case of an #{error}" do
        ssl.stubs(:read).raises(error).then.returns(42)
        subject.read
      end

      it "retries #write in the case of an #{error}" do
        ssl.stubs(:write).raises(error).then.returns(42)
        subject.write('abc123')
      end

      it 'raises the error if none of the retries work' do
        connection_options[:retries] = 1
        ssl.stubs(:read).raises(error).then.raises(error)
        -> { subject.read }.should raise_error(error)
      end
    end
  end

  it "clears the connection between retries" do
    ssl.stubs(:write).raises(Errno::EPIPE).then.returns(42)
    subject.write('abc123')
    ssl.should have_received(:close)
  end
end
