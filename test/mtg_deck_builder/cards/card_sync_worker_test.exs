defmodule MtgDeckBuilder.Cards.CardSyncWorkerTest do
  use ExUnit.Case, async: false

  alias MtgDeckBuilder.Cards.CardSyncWorker

  describe "status/0" do
    test "returns current worker state" do
      status = CardSyncWorker.status()

      assert is_map(status)
      assert Map.has_key?(status, :enabled)
      assert Map.has_key?(status, :syncing)
      assert Map.has_key?(status, :last_sync)
      assert Map.has_key?(status, :last_sync_result)
    end

    test "shows sync is disabled in test" do
      status = CardSyncWorker.status()
      assert status.enabled == false
    end
  end

  describe "sync_now/0" do
    test "returns :ok without error when disabled" do
      assert CardSyncWorker.sync_now() == :ok
    end
  end
end
