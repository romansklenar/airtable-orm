# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Collection, :airtable do
  # Reuse test models from associations spec
  class CollectionTestParent < Airtable::ORM::Base
    self.table_name = :client

    attribute :email, :string
    attribute :case_ids, :airtable_array

    has_many :children, class_name: "CollectionTestChild", foreign_key: :case_ids
  end

  class CollectionTestChild < Airtable::ORM::Base
    self.table_name = :case

    attribute :label, :string
  end

  def create_persisted_record(model_class, id:, attributes: {})
    record = model_class.new(**attributes)
    record.send(:assign_persistence_state, id: id, created_at: Time.iso8601("2024-01-01T00:00:00.000Z"),
                                           persisted: true)
    record.clear_changes_information
    record
  end

  let(:parent1) { create_persisted_record(CollectionTestParent, id: "recP1", attributes: { email: "p1@example.com" }) }
  let(:parent2) { create_persisted_record(CollectionTestParent, id: "recP2", attributes: { email: "p2@example.com" }) }

  describe "Array delegation" do
    it "behaves like an Array" do
      collection = described_class.new([parent1, parent2], model_class: CollectionTestParent)

      expect(collection.size).to eq(2)
      expect(collection.first).to eq(parent1)
      expect(collection.last).to eq(parent2)
      expect(collection.map(&:id)).to eq(%w[recP1 recP2])
    end

    it "supports iteration" do
      collection = described_class.new([parent1], model_class: CollectionTestParent)
      ids = collection.map(&:id)
      expect(ids).to eq(%w[recP1])
    end

    it "supports empty?" do
      expect(described_class.new([], model_class: CollectionTestParent)).to be_empty
      expect(described_class.new([parent1], model_class: CollectionTestParent)).not_to be_empty
    end
  end

  describe "#preload" do
    it "delegates to model_class.preload and returns self" do
      collection = described_class.new([parent1, parent2], model_class: CollectionTestParent)

      expect(CollectionTestParent).to receive(:preload).with(collection, :children)

      result = collection.preload(:children)
      expect(result).to be(collection)
    end

    it "supports chaining separate preload calls" do
      collection = described_class.new([parent1], model_class: CollectionTestParent)

      expect(CollectionTestParent).to receive(:preload).with(collection, :children).ordered
      expect(CollectionTestParent).to receive(:preload).with(collection, :primary_child).ordered

      result = collection.preload(:children).preload(:primary_child)
      expect(result).to be(collection)
    end

    it "passes multiple association names in one call" do
      collection = described_class.new([parent1], model_class: CollectionTestParent)

      expect(CollectionTestParent).to receive(:preload).with(collection, :children, :primary_child)

      collection.preload(:children, :primary_child)
    end
  end

  describe "querying integration" do
    it "returns a Collection from .all" do
      stub_list_records(records: [
                          { id: "recP1", fields: { "fldBn8I7io39SblLk" => "p1@example.com" },
                            createdTime: "2024-01-01T00:00:00.000Z" }
                        ])

      result = CollectionTestParent.all
      expect(result).to be_a(described_class)
      expect(result.model_class).to eq(CollectionTestParent)
    end

    it "returns a Collection from .where" do
      stub_list_records(records: [])

      result = CollectionTestParent.where(formula: "1=1")
      expect(result).to be_a(described_class)
    end

    def stub_list_records(records:)
      @stubs.post("/v0/appVntahBV9Q4evA7/tbl8MkbTpROqjERoD/listRecords") do
        [200, { "Content-Type" => "application/json" }, { records: records }.to_json]
      end
    end
  end

  describe "#model_class" do
    it "returns the stored model class" do
      collection = described_class.new([], model_class: CollectionTestParent)
      expect(collection.model_class).to eq(CollectionTestParent)
    end
  end

  describe "filtering preserves Collection type" do
    let(:collection) { described_class.new([parent1, parent2], model_class: CollectionTestParent) }

    it "#select returns a Collection" do
      result = collection.select { |r| r.id == "recP1" }
      expect(result).to be_a(described_class)
      expect(result.model_class).to eq(CollectionTestParent)
      expect(result.size).to eq(1)
    end

    it "#reject returns a Collection" do
      result = collection.reject { |r| r.id == "recP1" }
      expect(result).to be_a(described_class)
      expect(result.size).to eq(1)
      expect(result.first.id).to eq("recP2")
    end

    it "chaining preload after select works" do
      filtered = collection.select { |r| r.id == "recP1" }

      expect(CollectionTestParent).to receive(:preload).with(filtered, :children)

      filtered.preload(:children)
    end
  end
end
