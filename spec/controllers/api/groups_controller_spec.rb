describe Api::GroupsController do
  let!(:course) { create :course }
  let(:assignment) { create :assignment }
  let(:group) { create :group }
  let(:tag) { create :tag, course: course }
  context 'An unauthenticated request' do
    before :each do
      request.env['HTTP_AUTHORIZATION'] = 'garbage http_header'
      request.env['HTTP_ACCEPT'] = 'application/xml'
    end

    it 'should fail to authenticate a GET index request' do
      get :index, params: { assignment_id: assignment.id, course_id: course.id }
      expect(response).to have_http_status(403)
    end

    it 'should fail to authenticate a GET show request' do
      get :show, params: { assignment_id: assignment.id, id: group.id, course_id: course.id }
      expect(response).to have_http_status(403)
    end

    it 'should fail to authenticate a GET annotations request' do
      get :annotations, params: { assignment_id: assignment.id, id: group.id, course_id: course.id }
      expect(response).to have_http_status(403)
    end

    it 'should fail to authenticate a PUT add_tag request' do
      get :add_tag, params: { assignment_id: assignment.id, id: group.id, course_id: course.id, tag_id: tag.id }
      expect(response).to have_http_status(403)
    end

    it 'should fail to authenticate a PUT remove_tag request' do
      get :add_tag, params: { assignment_id: assignment.id, id: group.id, course_id: course.id, tag_id: tag.id }
      expect(response).to have_http_status(403)
    end
  end
  context 'An authenticated request requesting' do
    let(:grouping) { create :grouping_with_inviter, assignment: assignment }
    let(:instructor) { create :instructor }
    before :each do
      instructor.reset_api_key
      request.env['HTTP_AUTHORIZATION'] = "MarkUsAuth #{instructor.api_key.strip}"
    end
    shared_examples 'for a different course' do
      context 'an instructor for a different course' do
        let(:instructor) { create :instructor, course: create(:course) }
        it 'should return a 403 error' do
          expect(response).to have_http_status(403)
        end
      end
    end
    context 'GET index' do
      context 'expecting an xml response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/xml'
        end
        context 'with a single grouping' do
          before :each do
            get :index, params: { assignment_id: grouping.assignment.id, course_id: course.id }
          end
          it 'should be successful' do
            expect(response).to have_http_status(200)
          end
          it 'should return xml content' do
            expect(Hash.from_xml(response.body).dig('groups', 'group', 'id')).to eq(grouping.group.id.to_s)
          end
          it 'should return the member role id' do
            expect(Hash.from_xml(response.body).dig('groups', 'group', 'members', 'member',
                                                    'role_id')).to eq(grouping.student_memberships.first.role_id.to_s)
          end
          include_examples 'for a different course'
        end
        context 'with multiple assignments' do
          before :each do
            5.times { create :grouping_with_inviter, assignment: assignment }
            get :index, params: { assignment_id: assignment.id, course_id: course.id }
          end
          it 'should return xml content about all assignments' do
            expect(Hash.from_xml(response.body).dig('groups', 'group').length).to eq(5)
          end
          include_examples 'for a different course'
        end
      end
      context 'expecting a json response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/json'
        end
        context 'with a single assignment' do
          before :each do
            get :index, params: { assignment_id: grouping.assignment.id, course_id: course.id }
          end
          it 'should be successful' do
            expect(response).to have_http_status(200)
          end
          it 'should return json content' do
            expect(JSON.parse(response.body)&.first&.dig('id')).to eq(grouping.group.id)
          end
          it 'should return the member role id' do
            expect(JSON.parse(response.body)
                       .first['members'].first['role_id']).to eq(grouping.student_memberships.first.role_id)
          end
          include_examples 'for a different course'
        end
        context 'with multiple groupings' do
          let(:groupings) { Array.new(5) { create :grouping_with_inviter, assignment: assignment } }
          context 'for all groupings' do
            before { get :index, params: { assignment_id: assignment.id, course_id: course.id } }
            it 'should return content about all groupings' do
              groupings
              get :index, params: { assignment_id: assignment.id, course_id: course.id }
              expect(JSON.parse(response.body).length).to eq(5)
            end
            include_examples 'for a different course'
          end
          it 'should return only filtered content' do
            gr = groupings.first
            get :index, params: { assignment_id: gr.assignment.id, course_id: course.id,
                                  filter: { group_name: gr.group.group_name } }
            expect(JSON.parse(response.body)&.first&.dig('id')).to eq(gr.group.id)
          end
          it 'should not return groups that match the filter from another assignment' do
            get :index, params: { assignment_id: create(:assignment).id, course_id: course.id,
                                  filter: { group_name: groupings.last.group.group_name } }
            expect(JSON.parse(response.body)).to be_empty
          end
          it 'should reject invalid filters' do
            get :index, params: { assignment_id: groupings.first.assignment.id, course_id: course.id,
                                  filter: { bad_filter: 'something' } }
            expect(response).to have_http_status(422)
          end
        end
      end
    end
    context 'GET show' do
      context 'expecting an xml response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/xml'
        end
        context 'with a single grouping' do
          before :each do
            get :show, params: { id: grouping.group.id, assignment_id: grouping.assignment.id, course_id: course.id }
          end
          it 'should be successful' do
            expect(response).to have_http_status(200)
          end
          it 'should return xml content' do
            expect(Hash.from_xml(response.body).dig('groups', 'group', 'id')).to eq(grouping.group.id.to_s)
          end
          it 'should return the member role id' do
            expect(Hash.from_xml(response.body).dig('groups', 'group', 'members', 'member',
                                                    'role_id')).to eq(grouping.student_memberships.first.role_id.to_s)
          end
          include_examples 'for a different course'
        end
      end
      context 'expecting a json response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/json'
        end
        context 'with a single assignment' do
          before :each do
            get :show, params: { id: grouping.group.id, assignment_id: grouping.assignment.id, course_id: course.id }
          end
          it 'should be successful' do
            expect(response).to have_http_status(200)
          end
          it 'should return json content' do
            expect(JSON.parse(response.body)&.first&.dig('id')).to eq(grouping.group.id)
          end
          it 'should return the member role id' do
            expect(JSON.parse(response.body)
                       .first['members'].first['role_id']).to eq(grouping.student_memberships.first.role_id)
          end
          include_examples 'for a different course'
        end
      end
      context 'requesting a non-existant assignment' do
        it 'should respond with 404' do
          get :show, params: { id: 9999, assignment_id: assignment.id, course_id: course.id }
          expect(response).to have_http_status(404)
        end
      end
    end
    context 'POST add_new_members' do
      context 'when adding a student to an existing group with a member already' do
        let(:student) { create :student }
        before :each do
          post :add_members, params: { id: grouping.group.id,
                                       assignment_id: grouping.assignment.id,
                                       course_id: course.id,
                                       members: [student.user_name] }
        end
        include_examples 'for a different course'
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should add the student with accepted status' do
          expect(grouping.accepted_students).to include(student)
          status = grouping.accepted_student_memberships.find_by(role_id: student.id).membership_status
          expect(status).to eq(StudentMembership::STATUSES[:accepted])
        end
      end
      context 'when adding a student to an existing group without a member already' do
        let(:grouping) { create :grouping, assignment: assignment }
        let(:student) { create :student }
        before :each do
          post :add_members, params: { id: grouping.group.id,
                                       assignment_id: grouping.assignment.id,
                                       course_id: course.id,
                                       members: [student.user_name] }
        end
        include_examples 'for a different course'
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should add the student with inviter status' do
          expect(grouping.accepted_students).to include(student)
          status = grouping.accepted_student_memberships.find_by(role_id: student.id).membership_status
          expect(status).to eq(StudentMembership::STATUSES[:inviter])
        end
      end
      context 'when adding a student to a group without a grouping for this assignment' do
        let(:grouping) { create :grouping }
        let(:student) { create :student }
        before :each do
          post :add_members, params: { id: grouping.group.id,
                                       assignment_id: assignment.id,
                                       course_id: course.id,
                                       members: [student.user_name] }
        end
        include_examples 'for a different course'
        it 'should respond with 422' do
          expect(response).to have_http_status(422)
        end
        it 'should not add the student to the group' do
          expect(grouping.memberships).to be_empty
        end
      end
      context 'add multiple group members' do
        let(:students) { create_list(:student, 3) }
        before :each do
          post :add_members, params: { id: grouping.group.id,
                                       assignment_id: grouping.assignment.id,
                                       course_id: course.id,
                                       members: students.map(&:user_name) }
        end
        include_examples 'for a different course'
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should add the students with accepted status' do
          statuses = grouping.accepted_student_memberships.where(role_id: students.map(&:id)).pluck(:membership_status)
          expect(statuses).to all(be == StudentMembership::STATUSES[:accepted])
        end
      end
    end
    context 'POST update_marks' do
      let(:criterion) { create(:flexible_criterion, assignment: assignment, max_mark: 10) }
      let(:submission) { create(:version_used_submission, grouping: grouping) }
      context 'when a grouping does not yet have a mark' do
        before :each do
          submission
          post :update_marks, params: { id: grouping.group.id,
                                        assignment_id: grouping.assignment.id,
                                        course_id: course.id,
                                        criterion.name => 4 }
          grouping.reload
        end
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should add a mark for a grouping' do
          result = submission.current_result
          expect(result.get_total_mark).to eq(4)
        end
        include_examples 'for a different course'
      end
      context 'when a grouping does have a mark already' do
        before :each do
          mark = submission.current_result.marks.find_or_initialize_by(criterion_id: criterion.id)
          mark.mark = 10
          mark.save!
          post :update_marks, params: { id: grouping.group.id,
                                        assignment_id: grouping.assignment.id,
                                        course_id: course.id,
                                        criterion.name => 4 }
          grouping.reload
          submission.reload
        end
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should add a mark for a grouping' do
          result = submission.current_result
          expect(result.get_total_mark).to eq(4)
        end
        include_examples 'for a different course'
      end
      context 'when a result is complete' do
        before :each do
          mark = submission.current_result.marks.find_or_initialize_by(criterion_id: criterion.id)
          mark.mark = 10
          mark.save!
          submission.current_result.update(marking_state: Result::MARKING_STATES[:complete])
          post :update_marks, params: { id: grouping.group.id,
                                        assignment_id: grouping.assignment.id,
                                        course_id: course.id,
                                        criterion.name => 4 }
          grouping.reload
          submission.reload
        end
        it 'should respond with 404' do
          expect(response).to have_http_status(404)
        end
        it 'should add a mark for a grouping' do
          result = submission.current_result
          expect(result.get_total_mark).to eq(10)
        end
        include_examples 'for a different course'
      end
    end
    context 'POST add_extra_marks' do
      let(:submission) { create(:version_used_submission, grouping: grouping) }
      context 'add extra_mark' do
        let(:old_mark) { submission.get_latest_result.get_total_mark }
        before :each do
          old_mark
          post :create_extra_marks, params: { assignment_id: grouping.assignment.id,
                                              id: grouping.group.id,
                                              course_id: course.id,
                                              extra_marks: 10.0,
                                              description: 'sample' }
          grouping.reload
        end
        include_examples 'for a different course'
        it 'should add new extra mark' do
          result = submission.get_latest_result
          added_extra_mark = result.extra_marks.last
          expect(added_extra_mark.extra_mark).to eq(10.0)
        end
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
      end
      context 'add wrong extra_mark' do
        let(:old_mark) { submission.get_latest_result.get_total_mark }
        before :each do
          old_mark
          post :create_extra_marks, params: { assignment_id: grouping.assignment.id,
                                              id: grouping.group.id,
                                              course_id: course.id,
                                              extra_marks: 'a',
                                              description: 'sample' }
          grouping.reload
        end
        include_examples 'for a different course'
        it 'should respond with 500' do
          expect(response).to have_http_status(500)
        end
        it 'should not update the total mark' do
          result = submission.get_latest_result
          new_total_mark = result.get_total_mark
          expect(old_mark).to eq(new_total_mark)
        end
      end
      describe 'when the arguments are invalid' do
        context 'When the assignment has no submission' do
          it 'should respond with 404' do
            post :create_extra_marks,
                 params: { assignment_id: grouping.assignment.id, id: grouping.group.id, extra_marks: 10.0,
                           description: 'sample', course_id: course.id }
            expect(response).to have_http_status(404)
          end
        end
        context 'when the assignment doest not exist ' do
          it 'should respond with 404' do
            post :create_extra_marks,
                 params: { assignment_id: 9999, id: grouping.group.id,
                           extra_marks: 10.0, description: 'sample', course_id: course.id }
            expect(response).to have_http_status(404)
          end
        end
        context 'when the group does not exist' do
          it 'should respond with 404' do
            post :create_extra_marks,
                 params: { assignment_id: grouping.assignment.id, id: 9999,
                           extra_marks: 10.0, description: 'sample', course_id: course.id }
            expect(response).to have_http_status(404)
          end
        end
      end
    end
    context 'DELETE remove_extra_marks' do
      describe 'when the arguments are invalid' do
        context 'When the assignment has no submission' do
          it 'should respond with 404' do
            delete :remove_extra_marks,
                   params: { assignment_id: grouping.assignment.id, id: grouping.group.id, extra_marks: 10.0,
                             description: 'sample', course_id: course.id }
            expect(response).to have_http_status(404)
          end
        end
        context 'when the assignment doest not exist ' do
          it 'should respond with 404' do
            delete :remove_extra_marks,
                   params: { assignment_id: 9999, id: grouping.group.id,
                             extra_marks: 10.0, description: 'sample', course_id: course.id }
            expect(response).to have_http_status(404)
          end
        end
        context 'when the group does not exist' do
          it 'should respond with 404' do
            delete :remove_extra_marks,
                   params: { assignment_id: grouping.assignment.id, course_id: course.id,
                             id: 9999, extra_marks: 10.0, description: 'sample' }
            expect(response).to have_http_status(404)
          end
        end
      end
      describe 'when the arguments are valid' do
        let(:submission) { create(:version_used_submission, grouping: grouping) }
        let(:extra_mark) do
          create(:extra_mark_points, description: 'sample', extra_mark: 10.0, result: submission.get_latest_result)
        end
        context 'remove extra_mark' do
          let(:old_mark) { submission.get_latest_result.get_total_mark + extra_mark.extra_mark }
          before :each do
            old_mark
            delete :remove_extra_marks, params: { assignment_id: grouping.assignment.id,
                                                  id: grouping.group.id,
                                                  course_id: course.id,
                                                  extra_marks: 10.0,
                                                  description: 'sample' }
            grouping.reload
          end
          it 'should update total mark' do
            result = submission.get_latest_result
            new_total_mark = result.get_total_mark
            expect(old_mark - 10.0).to eq(new_total_mark)
          end
          it 'should respond with 200' do
            expect(response).to have_http_status(200)
          end
        end
        context 'remove extra_mark which does not exist' do
          let(:old_mark) { submission.get_latest_result.get_total_mark }
          before :each do
            old_mark
            delete :remove_extra_marks, params: { assignment_id: grouping.assignment.id,
                                                  id: grouping.group.id,
                                                  course_id: course.id,
                                                  extra_marks: 2.0,
                                                  description: 'test' }
            grouping.reload
          end
          it 'should respond with 404' do
            expect(response).to have_http_status(404)
          end
          it 'should not update the total mark' do
            result = submission.get_latest_result
            new_total_mark = result.get_total_mark
            expect(old_mark).to eq(new_total_mark)
          end
        end
      end
    end
    context 'GET group_ids_by_name' do
      context 'expecting a json response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/json'
          get :group_ids_by_name, params: { assignment_id: grouping.assignment.id, course_id: course.id }
        end
        include_examples 'for a different course'
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should return a mapping from group names to ids' do
          expect(JSON.parse(response.body)).to eq(grouping.group.group_name => grouping.group.id)
        end
      end
      context 'expecting a xml response' do
        before :each do
          request.env['HTTP_ACCEPT'] = 'application/xml'
          get :group_ids_by_name, params: { assignment_id: grouping.assignment.id, course_id: course.id }
        end
        include_examples 'for a different course'
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should return a mapping from group names to ids' do
          expect(Hash.from_xml(response.body)['groups']).to eq(grouping.group.group_name => grouping.group.id.to_s)
        end
      end
    end
    context 'POST update_marking_state' do
      let(:criterion) { create(:flexible_criterion, assignment: assignment, max_mark: 10) }
      let(:submission) { create(:version_used_submission, grouping: grouping) }
      context 'should complete a result' do
        before :each do
          submission.current_result.update(marking_state: Result::MARKING_STATES[:incomplete])
          post :update_marking_state, params: { id: grouping.group.id,
                                                assignment_id: grouping.assignment.id,
                                                course_id: course.id,
                                                marking_state: Result::MARKING_STATES[:complete] }
          submission.reload
        end
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should set the marking state to complete' do
          expect(submission.current_result.marking_state).to eq(Result::MARKING_STATES[:complete])
        end
        include_examples 'for a different course'
      end
      context 'should un-complete a result' do
        before :each do
          submission.current_result.update(marking_state: Result::MARKING_STATES[:complete])
          post :update_marking_state, params: { id: grouping.group.id,
                                                assignment_id: grouping.assignment.id,
                                                course_id: course.id,
                                                marking_state: Result::MARKING_STATES[:incomplete] }
          submission.reload
        end
        it 'should respond with 200' do
          expect(response).to have_http_status(200)
        end
        it 'should set the marking state to complete' do
          expect(submission.current_result.marking_state).to eq(Result::MARKING_STATES[:incomplete])
        end
        include_examples 'for a different course'
      end
    end
    describe 'GET annotations' do
      let(:grouping) { create :grouping, assignment: assignment }
      let(:submission) { create :version_used_submission, grouping: grouping }
      let(:submission_file) { create :submission_file, submission: submission }
      let!(:annotation) { create :text_annotation, submission_file: submission_file }
      let(:response_type) { 'application/xml' }
      before do
        request.env['HTTP_ACCEPT'] = response_type
        get :annotations, params: { assignment_id: assignment.id, id: group.id, course_id: course.id }
      end
      include_examples 'for a different course'
      it 'should get annotations for the given group' do
        skip 'fails on travis only'
        content = Hash.from_xml(response.body)
        expect(content.dig('annotations', 'annotation', 'content')).to eq annotation.annotation_text.content
      end
      it 'should respond with 200' do
        expect(response).to have_http_status(200)
      end
    end

    describe 'POST add_annotations' do
      let(:assignment) { create :assignment }
      let(:grouping) { create :grouping, assignment: assignment }
      let(:submission) { create :version_used_submission, grouping: grouping }
      let(:submission_file) { create :submission_file, submission: submission }
      let(:response_type) { 'application/xml' }

      it 'creates new annotations for a submission file that exists' do
        annotation_data = [
          {
            annotation_category_name: nil,
            filename: submission_file.filename,
            content: 'Content 1',
            line_start: 1,
            line_end: 1,
            column_start: 1,
            column_end: 5
          },
          {
            annotation_category_name: nil,
            filename: submission_file.filename,
            content: 'Content 2',
            line_start: 2,
            line_end: 2,
            column_start: 10,
            column_end: 15
          }
        ]
        request.env['HTTP_ACCEPT'] = response_type
        post :add_annotations, params: {
          assignment_id: assignment.id,
          id: grouping.group_id,
          course_id: course.id,
          annotations: annotation_data
        }

        expect(response).to have_http_status :success

        annotation_contents = submission.current_result.annotations.map { |a| a.annotation_text.content }
        expect(annotation_contents).to contain_exactly('Content 1', 'Content 2')
      end
    end
    context 'PUT remove_tag' do
      let(:response_type) { 'application/xml' }
      let(:tag) { create :tag, assessment: assignment }
      let(:grouping) { create :grouping, group: group, tags: [tag], assignment: assignment }

      before do
        request.env['HTTP_ACCEPT'] = response_type
      end

      it 'should let the user remove a tag' do
        put :remove_tag, params: { id: grouping.group.id, assignment_id: assignment.id,
                                   course_id: course.id, tag_id: tag.id }
        expect(response).to have_http_status(200)
        grouping.reload
        expect(grouping.tags.find_by(id: tag.id)).to be(nil)
      end

      it 'should throw a 404 if the grouping id is invalid not found' do
        put :remove_tag, params: { assignment_id: assignment.id, id: grouping.group.id + 1,
                                   course_id: course.id, tag_id: tag.id }
        grouping.reload

        expect(response).to have_http_status(404)
        expect(grouping.tags.first).to eq(tag)
      end

      it 'should throw a 404 if the tag id is not found' do
        put :remove_tag, params: { assignment_id: assignment.id, id: grouping.group.id,
                                   course_id: course.id, tag_id: tag.id + 1 }
        expect(response).to have_http_status(404)
        grouping.reload
        expect(grouping.tags.first).to eq(tag)
      end
    end

    context 'PUT add_tag' do
      let(:response_type) { 'application/xml' }
      let!(:tag) { create :tag, assessment: assignment }
      let(:grouping) { create :grouping, group: group, tags: [], assignment: assignment }
      before do
        request.env['HTTP_ACCEPT'] = response_type
      end

      it 'should let the user add a tag' do
        put :add_tag, params: { assignment_id: assignment.id, id: grouping.group.id,
                                course_id: course.id, tag_id: tag.id }
        expect(response).to have_http_status(200)
        grouping.reload
        expect(grouping.tags.first).to eq(tag)
      end

      it 'should throw a 404 if the grouping id is invalid not found' do
        put :add_tag, params: { assignment_id: assignment.id, id: grouping.group.id + 1,
                                course_id: course.id, tag_id: tag.id }
        expect(response).to have_http_status(404)
        expect(grouping.tags.first).to be(nil)
      end

      it 'should throw a 404 if the tag id is not found' do
        put :add_tag, params: { assignment_id: assignment.id, id: grouping.group.id,
                                course_id: course.id, tag_id: tag.id + 1 }
        expect(response).to have_http_status(404)
        expect(grouping.tags.first).to be(nil)
      end
    end
  end
end
