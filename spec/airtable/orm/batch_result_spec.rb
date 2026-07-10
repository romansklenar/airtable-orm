# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::BatchResult do
  describe "#initialize" do
    it "defaults to empty arrays" do
      result = described_class.new
      expect(result.updated).to eq([])
      expect(result.skipped).to eq([])
      expect(result.failed).to eq([])
    end

    it "accepts keyword arguments" do
      result = described_class.new(updated: [:a], skipped: [:b], failed: [:c])
      expect(result.updated).to eq([:a])
      expect(result.skipped).to eq([:b])
      expect(result.failed).to eq([:c])
    end
  end

  describe "#none_failed?" do
    it "returns true when no failures" do
      result = described_class.new(updated: %i[a b])
      expect(result.none_failed?).to be true
    end

    it "returns false when there are failures" do
      result = described_class.new(updated: [:a], failed: [:b])
      expect(result.none_failed?).to be false
    end
  end

  describe "#any_failed?" do
    it "returns true when there are failures" do
      result = described_class.new(failed: [:a])
      expect(result.any_failed?).to be true
    end

    it "returns false when no failures" do
      result = described_class.new(updated: [:a])
      expect(result.any_failed?).to be false
    end
  end

  describe "#total_count" do
    it "returns sum of updated, skipped, and failed" do
      result = described_class.new(updated: %i[a b], skipped: [:c], failed: [:d])
      expect(result.total_count).to eq(4)
    end

    it "returns 0 for empty result" do
      result = described_class.new
      expect(result.total_count).to eq(0)
    end
  end
end
