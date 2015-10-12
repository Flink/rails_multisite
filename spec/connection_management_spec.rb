require 'spec_helper'
require 'rails_multisite'

class Person < ActiveRecord::Base; end

describe RailsMultisite::ConnectionManagement do

  let(:conn){ RailsMultisite::ConnectionManagement }

  def with_connection(db)
    conn.establish_connection(db: db)
    yield ActiveRecord::Base.connection.raw_connection
  ensure
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end

  context 'default' do

    it 'has correct all_dbs' do
      expect(conn.all_dbs).to eq(['default'])
    end

    context 'current' do
      before do
        conn.establish_connection(db: 'default')
        ActiveRecord::Base.establish_connection
      end

      it "has default current db" do
        expect(conn.current_db).to eq('default')
      end

      it "has current hostname" do
        expect(conn.current_hostname).to eq('default.localhost')
      end

    end

  end

  context 'two dbs' do

    before do
      conn.config_filename = "spec/fixtures/two_dbs.yml"
      conn.load_settings!
    end

    it "has correct all_dbs" do
      expect(conn.all_dbs).to eq(['default', 'second'])
    end

    context 'second db' do
      before do
        conn.establish_connection(db: 'second')
      end

      it "is configured correctly" do
        expect(conn.current_db).to eq('second')
        expect(conn.current_hostname).to eq("second.localhost")
      end
    end

    context 'data partitioning' do
      after do
        ['default','second'].each do |db|
          with_connection(db) do |cnn|
            cnn.execute("drop table people") rescue nil
          end
        end
      end

      it 'partitions data correctly' do

        ['default','second'].map do |db|

          with_connection(db) do |cnn|
            cnn.execute("create table if not exists people(id INTEGER PRIMARY KEY AUTOINCREMENT, db)")
          end
        end

        SQLite3::Database.query_log.clear

        5.times do
          ['default','second'].map do |db|
            Thread.new do
              with_connection(db) do |cnn|
                Person.create!(db: db)
              end
            end
          end.map(&:join)
        end

        lists = []
        ['default', 'second'].each do |db|
          with_connection(db) do |cnn|
            lists << Person.order(:id).to_a.map{|p| [p.id, p.db]}
          end
        end

        expect(lists[1]).to eq((1..5).map{|id| [id, "second"]})
        expect(lists[0]).to eq((1..5).map{|id| [id, "default"]})

      end
    end
  end

end
