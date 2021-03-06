require "rails_helper"

RSpec.describe AccessLimit do
  subject do
    build(:access_limit,
      users: users,
      auth_bypass_ids: auth_bypass_ids,
    )
  end

  let(:users) { [SecureRandom.uuid] }
  let(:auth_bypass_ids) { [] }

  it { is_expected.to be_valid }

  describe "validates users" do
    context "where users has an array with a string" do
      let(:users) { [SecureRandom.uuid] }
      it { is_expected.to be_valid }
    end

    context "where users has an array with an integer" do
      let(:users) { [123] }
      it { is_expected.to be_invalid }
    end
  end

  describe "validates auth_bypass_ids" do
    context "where auth_bypass_ids has an array with a uuids" do
      let(:auth_bypass_ids) { [SecureRandom.uuid, SecureRandom.uuid] }
      it { is_expected.to be_valid }
    end

    context "where auth_bypass_ids has an array with non uuids" do
      let(:auth_bypass_ids) { ["not-a-uuid"] }
      it { is_expected.to be_invalid }
    end

    context "where users has an array with an integer" do
      let(:auth_bypass_ids) { [123] }
      it { is_expected.to be_invalid }
    end
  end
end
