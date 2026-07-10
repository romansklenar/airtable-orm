# frozen_string_literal: true

require "spec_helper"

RSpec.describe Airtable::ORM::Associations, :airtable do
  # Test models simulating Airtable relationships
  class TestParentModel < Airtable::ORM::Base
    self.table_name = :client

    attribute :email, :string
    attribute :case_ids, :airtable_array

    has_many :children, class_name: "TestChildModel", foreign_key: :case_ids
    has_one :primary_child, class_name: "TestChildModel", foreign_key: :case_ids
  end

  class TestChildModel < Airtable::ORM::Base
    self.table_name = :case

    attribute :label, :string
    attribute :client_ids, :airtable_array

    belongs_to :parent, class_name: "TestParentModel", foreign_key: :client_ids
  end

  # Helper to create a persisted record
  def create_persisted_record(model_class, id:, attributes: {})
    record = model_class.new(**attributes)
    record.send(:assign_persistence_state, id: id, created_at: Time.iso8601("2024-01-01T00:00:00.000Z"),
                                           persisted: true)
    record.clear_changes_information
    record
  end

  describe "has_many" do
    let(:parent) do
      create_persisted_record(TestParentModel, id: "recParent1", attributes: { email: "parent@example.com" })
    end
    let(:child1) { create_persisted_record(TestChildModel, id: "recChild1", attributes: { label: "Child 1" }) }
    let(:child2) { create_persisted_record(TestChildModel, id: "recChild2", attributes: { label: "Child 2" }) }
    let(:child3) { create_persisted_record(TestChildModel, id: "recChild3", attributes: { label: "Child 3" }) }

    describe "getter" do
      it "returns empty array when no associations" do
        parent.write_raw_attribute(:case_ids, nil)
        expect(parent.children).to eq([])

        parent.write_raw_attribute(:case_ids, [])
        expect(parent.children).to eq([])
      end

      it "returns associated records in correct (reversed) order" do
        # Store IDs in reverse order (API format)
        parent.write_raw_attribute(:case_ids, %w[recChild3 recChild2 recChild1])

        # Stub find_many to return records
        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2
                                                              recChild3]).and_return([child1, child2, child3])

        children = parent.children
        expect(children).to eq([child1, child2, child3])
      end

      it "uses find_many to load records" do
        parent.write_raw_attribute(:case_ids, %w[recChild2 recChild1])

        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2]).and_return([child1, child2])

        parent.children
      end

      it "memoizes has_many association to avoid repeated queries" do
        parent.write_raw_attribute(:case_ids, %w[recChild3 recChild2 recChild1])

        # First call should query
        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2
                                                              recChild3]).once.and_return([child1, child2, child3])

        # Multiple calls should use memoized value
        result1 = parent.children
        result2 = parent.children
        result3 = parent.children

        expect(result1).to eq([child1, child2, child3])
        expect(result2).to eq([child1, child2, child3])
        expect(result3).to eq([child1, child2, child3])
      end

      it "memoizes empty has_many associations" do
        parent.write_raw_attribute(:case_ids, [])

        # Should not call find_many for empty arrays, but should memoize the empty result
        expect(TestChildModel).not_to receive(:find_many)

        result1 = parent.children
        result2 = parent.children

        expect(result1).to eq([])
        expect(result2).to eq([])
      end
    end

    describe "setter" do
      it "accepts array of record objects and stores reversed IDs" do
        parent.children = [child1, child2, child3]

        # Should store in reverse order for API
        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild3 recChild2 recChild1])
      end

      it "accepts array of ID strings" do
        parent.children = %w[recChild1 recChild2]

        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild2 recChild1])
      end

      it "accepts mixed array of records and IDs" do
        parent.children = [child1, "recChild2", child3]

        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild3 recChild2 recChild1])
      end

      it "accepts empty array to clear association" do
        parent.write_raw_attribute(:case_ids, ["recChild1"])
        parent.children = []

        expect(parent.read_raw_attribute(:case_ids)).to eq([])
      end

      it "invalidates memoization cache when setter is called" do
        parent.write_raw_attribute(:case_ids, ["recChild1"])

        # First call memoizes
        expect(TestChildModel).to receive(:find_many).with(["recChild1"]).once.and_return([child1])
        expect(parent.children).to eq([child1])

        # Setter should clear cache
        parent.children = [child2, child3]

        # Next call should query again
        expect(TestChildModel).to receive(:find_many).with(%w[recChild2 recChild3]).once.and_return([child2, child3])
        expect(parent.children).to eq([child2, child3])
      end
    end

    describe "add_* method" do
      it "adds record to beginning of stored array (end of UI order)" do
        parent.write_raw_attribute(:case_ids, %w[recChild2 recChild1])

        parent.add_child(child3)

        # Should prepend to stored array
        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild3 recChild2 recChild1])
      end

      it "accepts record object" do
        parent.write_raw_attribute(:case_ids, [])

        parent.add_child(child1)

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild1"])
      end

      it "accepts ID string" do
        parent.write_raw_attribute(:case_ids, [])

        parent.add_child("recChild1")

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild1"])
      end

      it "handles nil current IDs" do
        parent.write_raw_attribute(:case_ids, nil)

        parent.add_child(child1)

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild1"])
      end

      it "invalidates memoization cache when add method is called" do
        parent.write_raw_attribute(:case_ids, ["recChild1"])

        expect(TestChildModel).to receive(:find_many).with(["recChild1"]).once.and_return([child1])
        expect(parent.children).to eq([child1])

        parent.add_child(child2)

        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2]).once.and_return([child1, child2])
        expect(parent.children).to eq([child1, child2])
      end
    end

    describe "remove_* method" do
      it "removes record from association" do
        parent.write_raw_attribute(:case_ids, %w[recChild3 recChild2 recChild1])

        parent.remove_child(child2)

        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild3 recChild1])
      end

      it "accepts record object" do
        parent.write_raw_attribute(:case_ids, %w[recChild2 recChild1])

        parent.remove_child(child1)

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild2"])
      end

      it "accepts ID string" do
        parent.write_raw_attribute(:case_ids, %w[recChild2 recChild1])

        parent.remove_child("recChild1")

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild2"])
      end

      it "handles removing non-existent record gracefully" do
        parent.write_raw_attribute(:case_ids, ["recChild1"])

        parent.remove_child("recChild999")

        expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild1"])
      end

      it "handles nil current IDs" do
        parent.write_raw_attribute(:case_ids, nil)

        parent.remove_child(child1)

        expect(parent.read_raw_attribute(:case_ids)).to eq([])
      end

      it "invalidates memoization cache when remove method is called" do
        parent.write_raw_attribute(:case_ids, %w[recChild2 recChild1])

        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2]).once.and_return([child1, child2])
        expect(parent.children).to eq([child1, child2])

        parent.remove_child(child2)

        expect(TestChildModel).to receive(:find_many).with(["recChild1"]).once.and_return([child1])
        expect(parent.children).to eq([child1])
      end
    end

    describe "reversal behavior maintains UI order" do
      it "double-reverse ensures correct order" do
        # Set records in UI order: [child1, child2, child3]
        parent.children = [child1, child2, child3]

        # Verify stored in reverse (API format)
        expect(parent.read_raw_attribute(:case_ids)).to eq(%w[recChild3 recChild2 recChild1])

        # Stub find_many to return in request order
        expect(TestChildModel).to receive(:find_many).with(%w[recChild1 recChild2
                                                              recChild3]).and_return([child1, child2, child3])

        # Getting should reverse back to UI order
        children = parent.children
        expect(children).to eq([child1, child2, child3])
      end
    end
  end

  describe "belongs_to" do
    let(:parent) do
      create_persisted_record(TestParentModel, id: "recParent1", attributes: { email: "parent@example.com" })
    end
    let(:child) { create_persisted_record(TestChildModel, id: "recChild1", attributes: { label: "Child" }) }

    describe "getter" do
      it "returns nil when no association" do
        child.write_raw_attribute(:client_ids, nil)
        expect(child.parent).to be_nil

        child.write_raw_attribute(:client_ids, [])
        expect(child.parent).to be_nil
      end

      it "returns single associated record" do
        child.write_raw_attribute(:client_ids, ["recParent1"])

        expect(TestParentModel).to receive(:find).with("recParent1").and_return(parent)

        expect(child.parent).to eq(parent)
      end

      it "uses find to load record" do
        child.write_raw_attribute(:client_ids, ["recParent1"])

        expect(TestParentModel).to receive(:find).with("recParent1").and_return(parent)

        child.parent
      end

      it "reverses array before taking first (UI order)" do
        # Even if stored with multiple IDs (shouldn't happen but handle it)
        child.write_raw_attribute(:client_ids, %w[recParent2 recParent1])

        # Should take first after reverse, which is "recParent1"
        expect(TestParentModel).to receive(:find).with("recParent1").and_return(parent)

        child.parent
      end

      it "memoizes belongs_to association to avoid repeated queries" do
        child.write_raw_attribute(:client_ids, ["recParent1"])

        expect(TestParentModel).to receive(:find).with("recParent1").once.and_return(parent)

        result1 = child.parent
        result2 = child.parent
        result3 = child.parent

        expect(result1).to eq(parent)
        expect(result2).to eq(parent)
        expect(result3).to eq(parent)
      end

      it "memoizes nil belongs_to associations" do
        child.write_raw_attribute(:client_ids, [])

        expect(TestParentModel).not_to receive(:find)

        result1 = child.parent
        result2 = child.parent

        expect(result1).to be_nil
        expect(result2).to be_nil
      end
    end

    describe "setter" do
      it "accepts record object" do
        child.parent = parent

        expect(child.read_raw_attribute(:client_ids)).to eq(["recParent1"])
      end

      it "accepts ID string" do
        child.parent = "recParent1"

        expect(child.read_raw_attribute(:client_ids)).to eq(["recParent1"])
      end

      it "with nil clears association" do
        child.write_raw_attribute(:client_ids, ["recParent1"])

        child.parent = nil

        expect(child.read_raw_attribute(:client_ids)).to eq([])
      end

      it "stores single ID in array format" do
        child.parent = parent

        # Verify it's stored as array, not a single value
        raw_value = child.read_raw_attribute(:client_ids)
        expect(raw_value).to be_a(Array)
        expect(raw_value).to eq(["recParent1"])
      end

      it "invalidates memoization cache when belongs_to setter is called" do
        child.write_raw_attribute(:client_ids, ["recParent1"])

        expect(TestParentModel).to receive(:find).with("recParent1").once.and_return(parent)
        expect(child.parent).to eq(parent)

        # Create a second parent for testing
        parent2 = create_persisted_record(TestParentModel, id: "recParent2",
                                                           attributes: { email: "parent2@example.com" })
        child.parent = parent2

        expect(TestParentModel).to receive(:find).with("recParent2").once.and_return(parent2)
        expect(child.parent).to eq(parent2)
      end
    end
  end

  describe "has_one" do
    let(:parent) do
      create_persisted_record(TestParentModel, id: "recParent1", attributes: { email: "parent@example.com" })
    end
    let(:child) { create_persisted_record(TestChildModel, id: "recChild1", attributes: { label: "Child" }) }

    it "is an alias for belongs_to" do
      # Verify has_one works the same as belongs_to
      parent.write_raw_attribute(:case_ids, ["recChild1"])

      expect(TestChildModel).to receive(:find).with("recChild1").and_return(child)

      expect(parent.primary_child).to eq(child)
    end

    it "setter works same as belongs_to" do
      parent.primary_child = child

      expect(parent.read_raw_attribute(:case_ids)).to eq(["recChild1"])
    end

    it "clears with nil" do
      parent.write_raw_attribute(:case_ids, ["recChild1"])

      parent.primary_child = nil

      expect(parent.read_raw_attribute(:case_ids)).to eq([])
    end
  end

  describe "avoids infinite recursion" do
    it "uses read_raw_attribute to bypass accessor methods" do
      parent = create_persisted_record(TestParentModel, id: "recParent1", attributes: { email: "parent@example.com" })
      parent.write_raw_attribute(:case_ids, ["recChild1"])

      # This should not cause infinite recursion
      expect(parent).to receive(:read_raw_attribute).with(:case_ids).and_call_original
      expect(TestChildModel).to receive(:find_many).with(["recChild1"]).and_return([])

      parent.children
    end
  end

  describe ".preload" do
    let(:child1) { create_persisted_record(TestChildModel, id: "recChild1", attributes: { label: "Child 1" }) }
    let(:child2) { create_persisted_record(TestChildModel, id: "recChild2", attributes: { label: "Child 2" }) }
    let(:parent1) do
      create_persisted_record(TestParentModel, id: "recParent1", attributes: { email: "p1@example.com" })
    end
    let(:parent2) do
      create_persisted_record(TestParentModel, id: "recParent2", attributes: { email: "p2@example.com" })
    end

    describe "has_many" do
      it "batch-fetches shared linked records in a single API call" do
        parent1.write_raw_attribute(:case_ids, ["recChild1"])
        parent2.write_raw_attribute(:case_ids, ["recChild1"])

        expect(TestChildModel).to receive(:find_many).with(["recChild1"]).once.and_return([child1])

        TestParentModel.preload([parent1, parent2], :children)

        # Subsequent access should use preloaded cache, no further API calls
        expect(TestChildModel).not_to receive(:find_many)
        expect(parent1.children).to eq([child1])
        expect(parent2.children).to eq([child1])
      end

      it "deduplicates IDs across records" do
        parent1.write_raw_attribute(:case_ids, %w[recChild2 recChild1])
        parent2.write_raw_attribute(:case_ids, ["recChild1"])

        expect(TestChildModel).to receive(:find_many) do |ids|
          expect(ids).to contain_exactly("recChild1", "recChild2")
          [child1, child2]
        end

        TestParentModel.preload([parent1, parent2], :children)

        expect(parent1.children).to eq([child1, child2])
        expect(parent2.children).to eq([child1])
      end

      it "handles records with no linked IDs" do
        parent1.write_raw_attribute(:case_ids, ["recChild1"])
        parent2.write_raw_attribute(:case_ids, [])

        expect(TestChildModel).to receive(:find_many).with(["recChild1"]).once.and_return([child1])

        TestParentModel.preload([parent1, parent2], :children)

        expect(parent1.children).to eq([child1])
        expect(parent2.children).to eq([])
      end

      it "skips API call when all records have empty associations" do
        parent1.write_raw_attribute(:case_ids, [])
        parent2.write_raw_attribute(:case_ids, nil)

        expect(TestChildModel).not_to receive(:find_many)

        TestParentModel.preload([parent1, parent2], :children)

        expect(parent1.children).to eq([])
        expect(parent2.children).to eq([])
      end
    end

    describe "belongs_to" do
      it "batch-fetches shared linked records in a single API call" do
        child1.write_raw_attribute(:client_ids, ["recParent1"])
        child2.write_raw_attribute(:client_ids, ["recParent1"])

        expect(TestParentModel).to receive(:find_many).with(["recParent1"]).once.and_return([parent1])

        TestChildModel.preload([child1, child2], :parent)

        expect(TestParentModel).not_to receive(:find)
        expect(child1.parent).to eq(parent1)
        expect(child2.parent).to eq(parent1)
      end

      it "handles nil associations" do
        child1.write_raw_attribute(:client_ids, ["recParent1"])
        child2.write_raw_attribute(:client_ids, [])

        expect(TestParentModel).to receive(:find_many).with(["recParent1"]).once.and_return([parent1])

        TestChildModel.preload([child1, child2], :parent)

        expect(child1.parent).to eq(parent1)
        expect(child2.parent).to be_nil
      end
    end

    it "does nothing for an empty collection" do
      expect(TestChildModel).not_to receive(:find_many)
      TestParentModel.preload([], :children)
    end

    it "raises for unknown association" do
      expect { TestParentModel.preload([parent1], :nonexistent) }.to raise_error(ArgumentError, /Unknown association/)
    end
  end
end
